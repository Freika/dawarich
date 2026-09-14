# Point move performance

The map's point-position command recalculates the containing Track and all of its TrackSegment geometry and metrics in the same database transaction. The server enforces a three-second transaction budget; a timeout rolls the complete edit back.

## Supported ceiling

Tracks containing up to 50,000 Points are the currently benchmarked synchronous-editing ceiling. Five out of five 50,000-Point runs completed inside the hard three-second budget. Larger Tracks are not rejected by size, but they are still subject to that budget.

The benchmark was run on 2026-09-14 against the local test PostgreSQL database with ten index-anchored TrackSegments per Track and five measured moves per size. `legacy` reconstructs the old Point update followed by the old background recalculation; it does not update TrackSegments or return canonical Track state, so it is a performance baseline rather than a feature-equivalent alternative.

| Variant | Points | Median | p95 / max | Queries | Median allocations | Track geometry | Max lock wait |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| legacy | 100 | 13.83 ms | 38.55 ms | 11 | 43,319 | 1,632 B | 0 ms |
| optimized | 100 | 24.90 ms | 44.85 ms | 29 | 76,615 | 1,632 B | 1.89 ms |
| legacy | 1,000 | 65.47 ms | 100.34 ms | 11 | 395,220 | 16,032 B | 0 ms |
| optimized | 1,000 | 82.68 ms | 120.36 ms | 29 | 651,553 | 16,032 B | 1.61 ms |
| legacy | 10,000 | 644.07 ms | 672.57 ms | 11 | 3,914,220 | 160,032 B | 0 ms |
| optimized | 10,000 | 568.54 ms | 612.66 ms | 29 | 6,400,753 | 160,032 B | 5.29 ms |
| legacy | 50,000 | 2,865.47 ms | 2,994.97 ms | 11 | 19,554,214 | 800,032 B | 0 ms |
| optimized | 50,000 | 2,361.23 ms | 2,488.59 ms | 29 | 31,952,755 | 800,032 B | 6.97 ms |

The new path performs more queries and allocations because it additionally locks revisions, resolves country membership, persists segment geometry, invalidates tiles, and publishes canonical state. Despite doing that extra work, it is faster than the legacy recalculation at 10,000 and 50,000 Points. The representative 10,000-Point p95 is 613 ms, below the one-second target; the 50,000-Point p95 is 2.49 seconds, below the hard budget. These local measurements establish implementation behavior, not a cross-host latency guarantee.

## Reproducing the benchmark

Run the benchmark on a disposable environment because it creates synthetic Points, Tracks, and TrackSegments. Its records are removed on completion.

```sh
RAILS_ENV=test bundle exec rails runner lib/perf/point_move_benchmark.rb
```

Override the sizes or use an existing synthetic user when needed:

```sh
POINT_MOVE_SIZES=100,1000 POINT_MOVE_RUNS=5 POINT_MOVE_USER_ID=123 \
  RAILS_ENV=test bundle exec rails runner lib/perf/point_move_benchmark.rb
```

Use `POINT_MOVE_VARIANTS=legacy`, `optimized`, or both to select the path. Each output line is JSON and reports the variant, duration, SQL query count, Ruby allocations, Track geometry size, TrackSegment count, and database lock wait. A summary line reports median and nearest-rank p95 values. The `point_move.map` notification exposes the corresponding production outcome and timing metrics without coordinates or user identifiers.
