# Tracks Feature Performance Optimization Options

## Current State Analysis

### Performance Characteristics
- **Time Complexity:** O(n log n) where n = number of GPS points
- **Memory Usage:** Loads entire dataset into memory (~200-400 bytes per point)
- **Processing Mode:** Single-threaded, sequential segmentation
- **Database Load:** Multiple PostGIS distance calculations per point pair

### Performance Estimates (Bulk Mode)
| Points | Processing Time | Memory Usage | Database Load |
|--------|----------------|--------------|---------------|
| 10K    | 30-60 seconds  | ~50 MB      | Low          |
| 100K   | 5-15 minutes   | ~200 MB     | Medium       |
| 1M+    | 30-90 minutes  | 400+ MB     | High         |

### Current Bottlenecks
1. **Memory constraints** - Loading all points at once
2. **PostGIS distance calculations** - Sequential, not optimized
3. **Single-threaded processing** - No parallelization
4. **No progress indication** - Users can't track long-running operations

---

## Optimization Options

### Option 1: Enhanced Time-Based Batching
**Complexity:** Low | **Impact:** High | **Risk:** Low

#### Implementation
- Extend existing `:daily` mode with configurable batch sizes
- Add 1-point overlap between batches to maintain segmentation accuracy
- Implement batch-aware progress reporting

#### Benefits
- **Memory reduction:** 90%+ reduction (from 400MB to ~40MB for 1M points)
- **Better UX:** Progress indication and cancellation support
- **Incremental processing:** Can resume interrupted operations
- **Lower DB pressure:** Smaller query result sets

#### Changes Required
```ruby
# Enhanced generator with configurable batching
Tracks::Generator.new(
  user, 
  mode: :batched,
  batch_size: 24.hours,
  enable_overlap: true
).call
```

#### Edge Cases to Handle
- Tracks spanning batch boundaries (solved with overlap)
- Midnight-crossing tracks in daily mode
- Deduplication of overlapping segments

---

### Option 2: Spatial Indexing Optimization
**Complexity:** Medium | **Impact:** Medium | **Risk:** Low

#### Implementation
- Replace individual PostGIS calls with batch distance calculations
- Implement spatial clustering for nearby points before segmentation
- Use PostGIS window functions for distance calculations

#### Benefits
- **Faster distance calculations:** Batch operations vs individual queries
- **Reduced DB round-trips:** Single query for multiple distance calculations
- **Better index utilization:** Leverage existing spatial indexes

#### Changes Required
```sql
-- Batch distance calculation approach
WITH point_distances AS (
  SELECT 
    id,
    timestamp,
    ST_Distance(
      lonlat::geography,
      LAG(lonlat::geography) OVER (ORDER BY timestamp)
    ) as distance_to_previous
  FROM points 
  WHERE user_id = ? 
  ORDER BY timestamp
)
SELECT * FROM point_distances WHERE distance_to_previous > ?
```

---

### Option 3: Parallel Processing with Worker Pools
**Complexity:** High | **Impact:** High | **Risk:** Medium

#### Implementation
- Split large datasets into non-overlapping time ranges
- Process multiple batches in parallel using Sidekiq workers
- Implement coordination mechanism for dependent segments

#### Benefits
- **Faster processing:** Utilize multiple CPU cores
- **Scalable:** Performance scales with worker capacity
- **Background processing:** Non-blocking for users

#### Challenges
- **Complex coordination:** Managing dependencies between batches
- **Resource competition:** Multiple workers accessing same user's data
- **Error handling:** Partial failure scenarios

#### Architecture
```ruby
# Parallel processing coordinator
class Tracks::ParallelGenerator
  def call
    time_ranges = split_into_parallel_ranges
    
    time_ranges.map do |range|
      Tracks::BatchProcessorJob.perform_later(user_id, range)
    end
  end
end
```

---

### Option 4: Incremental Algorithm Enhancement
**Complexity:** Medium | **Impact:** Medium | **Risk:** Medium

#### Implementation
- Enhance existing `:incremental` mode with smarter buffering
- Implement sliding window approach for active track detection
- Add automatic track finalization based on time gaps

#### Benefits
- **Real-time processing:** Process points as they arrive
- **Lower memory footprint:** Only active segments in memory
- **Better for live tracking:** Immediate track updates

#### Current Limitations
- Existing incremental mode processes untracked points only
- No automatic track finalization
- Limited to single active track per user

---

### Option 5: Database-Level Optimization
**Complexity:** Low-Medium | **Impact:** Medium | **Risk:** Low

#### Implementation
- Add composite indexes for common query patterns
- Implement materialized views for expensive calculations
- Use database-level segmentation logic

#### Benefits
- **Faster queries:** Better index utilization
- **Reduced Ruby processing:** Move logic to database
- **Consistent performance:** Database optimizations benefit all modes

#### Proposed Indexes
```sql
-- Optimized for bulk processing
CREATE INDEX CONCURRENTLY idx_points_user_timestamp_track 
ON points(user_id, timestamp) WHERE track_id IS NULL;

-- Optimized for incremental processing
CREATE INDEX CONCURRENTLY idx_points_untracked_timestamp 
ON points(timestamp) WHERE track_id IS NULL;
```

---

## Recommended Implementation Strategy

### Phase 1: Quick Wins (Week 1-2)
1. **Implement Enhanced Time-Based Batching** (Option 1)
   - Extend existing daily mode with overlap
   - Add progress reporting
   - Configurable batch sizes

### Phase 2: Database Optimization (Week 3)
2. **Add Database-Level Optimizations** (Option 5)
   - Create optimized indexes
   - Implement batch distance calculations

### Phase 3: Advanced Features (Week 4-6)
3. **Spatial Indexing Optimization** (Option 2)
   - Replace individual distance calculations
   - Implement spatial clustering

### Phase 4: Future Enhancements
4. **Parallel Processing** (Option 3) - Consider for v2
5. **Incremental Enhancement** (Option 4) - For real-time features

---

## Risk Assessment

### Low Risk
- **Time-based batching:** Builds on existing daily mode
- **Database indexes:** Standard optimization technique
- **Progress reporting:** UI enhancement only

### Medium Risk
- **Spatial optimization:** Requires careful testing of distance calculations
- **Incremental enhancement:** Changes to existing algorithm logic

### High Risk
- **Parallel processing:** Complex coordination, potential race conditions
- **Major algorithm changes:** Could introduce segmentation bugs

---

## Success Metrics

### Performance Targets
- **Memory usage:** < 100MB for datasets up to 1M points
- **Processing time:** < 10 minutes for 1M points
- **User experience:** Progress indication and cancellation

### Monitoring Points
- Database query performance
- Memory consumption during processing
- User-reported processing times
- Track generation accuracy (no regression)

---

## Next Steps

1. **Choose initial approach** based on urgency and resources
2. **Create feature branch** for selected optimization
3. **Implement comprehensive testing** including edge cases
4. **Monitor performance** in staging environment
5. **Gradual rollout** with feature flags