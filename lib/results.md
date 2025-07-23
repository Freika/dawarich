## Original

Generator: created track 227296
Generated 1437 tracks for user 1 in bulk mode
✅ Generation completed successfully

============================================================
📊 BENCHMARK RESULTS
============================================================
Status: ✅ SUCCESS
Execution Time: 1m 28.5s
Tracks Created: 1437
Timeframe Coverage: 8.0% of user's total data

💾 Memory Usage:
  Start: 210.9MB
  End: 433.2MB
  Memory Increase: +222.3MB

🗄️  Database Performance:
  Total Queries: 115920
  Total Query Time: 50453.1ms
  Average Query Time: 0.44ms
  Slow Queries (>100ms): 63
    1. 983.24ms - SELECT COUNT(*) FROM "points" WHERE "points"."user_id" = $1 AND "points"."timestamp" BETWEEN $2 A...
    2. 2826.02ms - SELECT "points".* FROM "points" WHERE "points"."user_id" = $1 AND "points"."timestamp" BETWEEN $2...
    3. 217.02ms - UPDATE "points" SET "track_id" = $1 WHERE "points"."id" IN ($2, $3, $4, $5, $6, $7, $8, $9, $10, ...

✔️  Post-Generation Validation:
  Points in Timeframe: 111609
  Points with Tracks: 110167
  Points without Tracks: 1442
  Track Records: 1437
  ✅ Data integrity: PASS

🔍 Performance Analysis:
  Speed Rating: 🚀 Excellent (1m 28.5s)
  Memory Rating: 🧡 High (433.2MB peak)
  Recommendation: Consider database optimization or smaller batch sizes

🔮 Extrapolation for Full Dataset:
  Full Dataset Size: 1,403,662 points
  Scaling Factor: 12.6x
  Estimated Full Time: 18m 32.8s
  Estimated Full Memory: 5447.6MB

============================================================
📋 BENCHMARK SUMMARY
============================================================
⏱️  Total Time: 1m 28.5s
📍 Points Processed: 111,609
🛤️  Tracks Created: 1437
🚀 Processing Speed: 1261.4 points/second
📅 Timeframe: 2024-01-01 to 2024-12-31
👤 User: demo@dawarich.app (ID: 1)
✅ Status: COMPLETED


## Iteration 1

Generator: created track 244784
Generated 1435 tracks for user 1 in optimized bulk mode
✅ Generation completed successfully

============================================================
📊 BENCHMARK RESULTS
============================================================
Status: ✅ SUCCESS
Execution Time: 56.4s
Tracks Created: 1435
Points Processed: 111,609
Processing Speed: 1978.3 points/second
Average Points/Track: 77.8
Timeframe Coverage: 8.0% of user's total data

💾 Memory Usage:
  Start: 297.2MB
  End: 407.5MB
  Memory Increase: +110.3MB

🗄️  Database Performance:
  Total Queries: 7178
  Total Query Time: 44521.33ms
  Average Query Time: 6.2ms
  Slow Queries (>100ms): 88
    1. 2338.43ms - WITH points_with_gaps AS (
  SELECT
    id,
    timestamp,
    lonlat,
    LAG(lonlat) OVER (ORDE...
    2. 4156.84ms - SELECT "points".* FROM "points" WHERE "points"."id" IN (2163775, 2163776, 2163777, 2163778, 21637...
    3. 298.62ms - UPDATE "points" SET "track_id" = $1 WHERE "points"."id" IN ($2, $3, $4, $5, $6, $7, $8, $9, $10, ...

✔️  Post-Generation Validation:
  Points in Timeframe: 111609
  Points with Tracks: 110123
  Points without Tracks: 1486
  Track Records: 1435
  ✅ Data integrity: PASS

🔍 Performance Analysis:
  Speed Rating: 🚀 Excellent (56.4s)
  Memory Rating: 🧡 High (407.5MB peak)
  Recommendation: Consider database optimization or smaller batch sizes

🔮 Extrapolation for Full Dataset:
  Full Dataset Size: 1,403,662 points
  Scaling Factor: 12.6x
  Estimated Full Time: 11m 49.5s
  Estimated Full Memory: 5125.0MB

============================================================
📋 BENCHMARK SUMMARY
============================================================
⏱️  Total Time: 56.4s
📍 Points Processed: 111,609
🛤️  Tracks Created: 1435
🚀 Processing Speed: 1978.3 points/second
📅 Timeframe: 2024-01-01 to 2024-12-31
👤 User: demo@dawarich.app (ID: 1)
✅ Status: COMPLETED
