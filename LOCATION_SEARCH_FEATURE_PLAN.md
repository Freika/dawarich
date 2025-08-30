# Location Search Feature Implementation Plan

## Overview
Implement a location search feature allowing users to search for places (e.g., "Kaufland", "Schneller straße 130") and find when they visited those locations based on their recorded points data.

## Current System Analysis

### Existing Infrastructure
- **Database**: PostgreSQL with PostGIS extension
- **Geocoding**: Geocoder gem with multiple providers (Photon, Geoapify, Nominatim, LocationIQ)  
- **Geographic Data**: Points with `lonlat` (PostGIS geometry), `latitude`, `longitude` columns
- **Indexes**: GIST spatial indexes on `lonlat` columns for efficient spatial queries
- **Places Model**: Stores geocoded places with `geodata` JSONB field (OSM metadata)
- **Points Model**: Basic location data with `city`, `country` text fields (geodata field exists but empty)

### Key Constraints
- Points table does **NOT** store geocoded metadata in `points.geodata` (confirmed empty)
- Must rely on coordinate-based spatial matching rather than text-based search within points
- Places table contains rich geodata for places, but points are coordinate-only

## Implementation Approach

### 1. Two-Stage Search Strategy

#### Stage 1: Forward Geocoding (Query → Coordinates)
```
User Query → Geocoding Service → Geographic Candidates
"Kaufland" → Photon API → [{lat: 52.5200, lon: 13.4050, name: "Kaufland Mitte"}, ...]
```

#### Stage 2: Spatial Point Matching (Coordinates → User Points) 
```
Geographic Candidates → PostGIS Spatial Query → User's Historical Points
[{lat: 52.5200, lon: 13.4050}] → ST_DWithin(points.lonlat, candidate, radius) → Points with timestamps
```

### 2. Architecture Components

#### New Service Classes
```
app/services/location_search/
├── point_finder.rb          # Main orchestration service
├── geocoding_service.rb     # Forward geocoding via existing Geocoder
├── spatial_matcher.rb       # PostGIS spatial queries
└── result_aggregator.rb     # Group and format results
```

#### Controller Enhancement
```
app/controllers/api/v1/locations_controller.rb#index (enhanced with search functionality)
```

#### New Serializers
```
app/serializers/location_search_result_serializer.rb
```

### 3. Database Query Strategy

#### Primary Spatial Query
```sql
-- Find user points within radius of searched location
SELECT 
  p.id,
  p.timestamp,
  p.latitude,
  p.longitude,
  p.city,
  p.country,
  ST_Distance(p.lonlat, ST_Point(?, ?)::geography) as distance_meters
FROM points p
WHERE p.user_id = ?
  AND ST_DWithin(p.lonlat, ST_Point(?, ?)::geography, ?)
ORDER BY p.timestamp DESC;
```

#### Smart Radius Selection
- **Specific businesses** (Kaufland, McDonald's): 50-100m radius
- **Street addresses**: 25-75m radius  
- **Neighborhoods/Areas**: 200-500m radius
- **Cities/Towns**: 1000-2000m radius

### 4. API Design

#### Endpoint
```
GET /api/v1/locations (enhanced with search parameter)
```

#### Parameters
```json
{
  "q": "Kaufland",              // Search query (required)
  "limit": 50,                  // Max results per location (default: 50)
  "date_from": "2024-01-01",    // Optional date filtering
  "date_to": "2024-12-31",      // Optional date filtering
  "radius_override": 200        // Optional radius override in meters
}
```

#### Response Format
```json
{
  "query": "Kaufland",
  "locations": [
    {
      "place_name": "Kaufland Mitte",
      "coordinates": [52.5200, 13.4050],
      "address": "Alexanderplatz 1, Berlin",
      "total_visits": 15,
      "first_visit": "2024-01-15T09:30:00Z",
      "last_visit": "2024-03-20T18:45:00Z",
      "visits": [
        {
          "timestamp": 1640995200,
          "date": "2024-03-20T18:45:00Z",
          "coordinates": [52.5201, 13.4051],
          "distance_meters": 45,
          "duration_estimate": "~25 minutes",
          "points_count": 8
        }
      ]
    }
  ],
  "total_locations": 3,
  "search_metadata": {
    "geocoding_provider": "photon",
    "candidates_found": 5,
    "search_time_ms": 234
  }
}
```

## Implementation Plan

### Phase 1: Core Search Infrastructure
1. **Service Layer**
   - `LocationSearch::PointFinder` - Main orchestration
   - `LocationSearch::GeocodingService` - Forward geocoding wrapper
   - `LocationSearch::SpatialMatcher` - PostGIS queries

2. **API Layer**
   - Enhanced `Api::V1::LocationsController#index` with search functionality
   - Request validation and parameter handling
   - Response serialization

3. **Database Optimizations**
   - Verify spatial indexes are optimal
   - Add composite indexes if needed

### Phase 2: Smart Features
1. **Visit Clustering**
   - Group consecutive points into "visits" 
   - Estimate visit duration and patterns
   - Detect multiple visits to same location

2. **Enhanced Geocoding**
   - Multiple provider fallback
   - Result caching and optimization
   - Smart radius selection based on place type

3. **Result Filtering**
   - Date range filtering
   - Minimum visit duration filtering  
   - Relevance scoring

### Phase 3: Frontend Integration
1. **Map Integration**
   - Search bar component on map page
   - Auto-complete with suggestions
   - Visual highlighting of found locations

2. **Results Display**
   - Timeline view of visits
   - Click to zoom/highlight on map
   - Export functionality

## Test Coverage Requirements

### Unit Tests

#### LocationSearch::PointFinder
```ruby
describe LocationSearch::PointFinder do
  describe '#call' do
    context 'with valid business name query' do
      it 'returns matching points within reasonable radius'
      it 'handles multiple location candidates'
      it 'respects user data isolation'
    end

    context 'with address query' do
      it 'uses appropriate radius for address searches'
      it 'handles partial address matches'
    end

    context 'with no geocoding results' do
      it 'returns empty results gracefully'
    end

    context 'with no matching points' do
      it 'returns location but no visits'
    end
  end
end
```

#### LocationSearch::SpatialMatcher
```ruby
describe LocationSearch::SpatialMatcher do
  describe '#find_points_near' do
    it 'finds points within specified radius using PostGIS'
    it 'excludes points outside radius'
    it 'orders results by timestamp'
    it 'filters by user correctly'
    it 'handles edge cases (poles, date line)'
  end

  describe '#cluster_visits' do
    it 'groups consecutive points into visits'
    it 'calculates visit duration correctly'
    it 'handles single-point visits'
  end
end
```

#### LocationSearch::GeocodingService
```ruby
describe LocationSearch::GeocodingService do
  describe '#search' do
    context 'when geocoding succeeds' do
      it 'returns normalized location results'
      it 'handles multiple providers (Photon, Nominatim)'
      it 'caches results appropriately'
    end

    context 'when geocoding fails' do
      it 'handles API timeouts gracefully'
      it 'falls back to alternative providers'
      it 'returns meaningful error messages'
    end
  end
end
```

### Integration Tests

#### API Controller Tests
```ruby
describe Api::V1::LocationsController do
  describe 'GET #index' do
    context 'with authenticated user' do
      it 'returns search results for existing locations'
      it 'respects date filtering parameters'
      it 'handles pagination correctly'
      it 'validates search parameters'
    end

    context 'with unauthenticated user' do
      it 'returns 401 unauthorized'
    end

    context 'with cross-user data' do
      it 'only returns current user points'
    end
  end
end
```

### System Tests

#### End-to-End Scenarios
```ruby
describe 'Location Search Feature' do
  scenario 'User searches for known business' do
    # Setup user with historical points near Kaufland
    # Navigate to map page  
    # Enter "Kaufland" in search
    # Verify results show historical visits
    # Verify map highlights correct locations
  end

  scenario 'User searches with date filtering' do
    # Test date range functionality
  end

  scenario 'User searches for location with no visits' do
    # Verify graceful handling of no results
  end
end
```

### Performance Tests

#### Database Query Performance
```ruby
describe 'Location Search Performance' do
  context 'with large datasets' do
    before { create_list(:point, 100_000, user: user) }

    it 'completes spatial queries within 500ms'
    it 'maintains performance with multiple concurrent searches'
    it 'uses spatial indexes effectively'
  end
end
```

### Edge Case Tests

#### Geographic Edge Cases
- Searches near poles (high latitude)
- Searches crossing date line (longitude ±180°)
- Searches in areas with dense point clusters
- Searches with very large/small radius values

#### Data Edge Cases
- Users with no points
- Points with invalid coordinates
- Geocoding service returning invalid data
- Malformed search queries

## Security Considerations

### Data Isolation
- Ensure users can only search their own location data
- Validate user authentication on all endpoints
- Prevent information leakage through error messages

### Rate Limiting
- Implement rate limiting for search API to prevent abuse
- Cache geocoding results to reduce external API calls
- Monitor and limit expensive spatial queries

### Input Validation
- Sanitize and validate all search inputs
- Prevent SQL injection via parameterized queries
- Limit search query length and complexity

## Performance Optimization

### Database Optimizations
- Ensure optimal GIST indexes on `points.lonlat`
- Consider partial indexes for active users
- Monitor query performance and add indexes as needed

### Caching Strategy
- Cache geocoding results (already implemented in Geocoder)
- Consider caching frequent location searches
- Use Redis for session-based search result caching

### Query Optimization
- Use spatial indexes for all PostGIS queries
- Implement pagination for large result sets
- Consider pre-computed search hints for popular locations

## Future Enhancements

### Advanced Search Features
- Fuzzy/typo-tolerant search
- Search by business type/category
- Search within custom drawn areas
- Historical search trends

### Machine Learning Integration
- Predict likely search locations for users
- Suggest places based on visit patterns
- Automatic place detection and naming

### Analytics and Insights
- Most visited places for user
- Time-based visitation patterns
- Location-based statistics and insights

## Risk Assessment

### High Risk
- **Performance**: Large spatial queries on million+ point datasets
- **Geocoding Costs**: External API usage costs and rate limits
- **Data Accuracy**: Matching accuracy with radius-based approach

### Medium Risk  
- **User Experience**: Search relevance and result quality
- **Scalability**: Concurrent user search performance
- **Maintenance**: Multiple geocoding provider maintenance

### Low Risk
- **Security**: Standard API security with existing patterns
- **Integration**: Building on established PostGIS infrastructure
- **Testing**: Comprehensive test coverage achievable

## Success Metrics

### Functional Metrics
- Search result accuracy > 90% for known locations
- Average response time < 500ms for typical searches
- Support for 95% of common place name and address formats

### User Experience Metrics
- User engagement with search feature
- Search-to-map-interaction conversion rate
- User retention and feature adoption

### Technical Metrics
- API endpoint uptime > 99.9%
- Database query performance within SLA
- Geocoding provider reliability and failover success