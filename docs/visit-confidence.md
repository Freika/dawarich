# Visit confidence and legacy points

Full-history redetection preserves confirmed visits and backfills missing confidence from their own coordinate-bearing points. Points whose `lonlat` is NULL do not contribute to point count, accuracy, center, or radius. This applies to direct `Visits::Detection::VisitRescore.call`, explicitly preloaded point sets, legacy backfill, and batch-edge stitching.

When no coordinate-bearing points remain, rescoring leaves the visit and its existing confidence/breakdown unchanged. A legacy visit with no score stays unscored and retains its existing visibility and status; no score is invented from an Area or Place alone. Valid observations retain the existing confidence rules.

Legacy backfill reads slim point rows once per 200 visits and preloads Area/Place associations. Stitch centers also use batched projections. These filters do not repair or delete old point records, change `Point#lat`/`#lon`, or suppress unrelated job errors. No migration or automatic replay of previously failed jobs is included. An operator can retry a failed visit-redetection job after upgrading, or the user can request full-history redetection again.

Regression coverage lives in `spec/services/visits/detection/visit_rescore_spec.rb`, `history_redetect_spec.rb`, `runner_spec.rb`, and `spec/regressions/history_redetect_skips_points_without_coordinates_spec.rb`. The latter exercises `Visits::UserRedetectJob` completion with synthetic historical records.

Related issue: https://github.com/Freika/dawarich/issues/3931
Shared engineering index: AFFiNE “Dawarich — Open issue priorities” (`2tgruNB7k104KlD136MUh`).
