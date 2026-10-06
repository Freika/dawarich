# Exports and user-data closure

The native `POST /exports` handler accepts the captured Rails scalar values under
native ownership, including archive rows without a points job and blank formats
with their source callback. It preserves date normalization, failure status 422,
redirect location, and alert cookies. Source ownership retains the existing
coexistence behavior. Native write failures roll back and return the source error
without replay.

Backup and restore use the current authenticated user independently of the settings
ownership key. The import pipeline uses the existing A8 form decoder through its
domain gate to reach the source container-error redirects. The one-line
`UserDataRoutes` change is minimal package wiring; O06–O08 still own final routing.

E01 and E04 have aggregate tagged tests, initial missing-behavior failures, passing
results, named mutation failures and restored passes. The existing source-backed
native batch passed 71 tests at the base. Remaining E02–E11 closure and shared
cache/effect dependencies are under review; this document does not claim package
or Ruby-free release acceptance.

The current-head E04 generator was extended with array/object archive errors.
Its existing named example captures these inputs; no new generator test was added.
The implementation report records the two writes and their byte comparison.
