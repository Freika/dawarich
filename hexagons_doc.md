# Hexagonal Grid Overlay Implementation

This implementation adds a hexagonal grid overlay to the Leaflet map in your Ruby on Rails + PostGIS project. The grid displays ~1km hexagons that dynamically load based on the current map viewport.

## Components

### 1. Backend - Rails API Controller

**File**: `app/controllers/api/v1/maps/hexagons_controller.rb`

**Endpoint**: `GET /api/v1/maps/hexagons`

**Authentication**: Requires valid API key

**Parameters**:
- `api_key`: User's API key (required)
- `min_lon`, `min_lat`, `max_lon`, `max_lat`: Bounding box coordinates

**Features**:
- Generates hexagons using PostGIS `ST_HexagonGrid`
- 1km edge-to-edge hexagon size (~500m center-to-edge)
- Maximum 5000 hexagons per request for performance
- Validates bounding box size and coordinates
- Handles edge cases (large areas, invalid coordinates)
- Returns GeoJSON FeatureCollection

### 2. Frontend - JavaScript Module

**File**: `app/javascript/maps/hexagon_grid.js`

**Key Features**:
- Efficient viewport-based loading with debouncing
- Zoom-level restrictions (min: 8, max: 16)
- Automatic cleanup and memory management
- Hover effects and click handling
- Request cancellation for pending requests

### 3. Integration

**File**: `app/javascript/controllers/maps_controller.js` (modified)

**Integration Points**:
- Import and initialize hexagon grid
- Add to layer control
- Event handling for layer toggle
- Cleanup on disconnect

## Usage

### Basic Usage

The hexagon grid will be available as a layer in the map's layer control panel. Users can toggle it on/off via the "Hexagon Grid" checkbox.

### Programmatic Control

```javascript
// Show hexagons
controller.hexagonGrid.show();

// Hide hexagons
controller.hexagonGrid.hide();

// Toggle visibility
controller.hexagonGrid.toggle();

// Update styling
controller.hexagonGrid.updateStyle({
  fillColor: '#ff0000',
  fillOpacity: 0.2,
  color: '#ff0000',
  weight: 2,
  opacity: 0.8
});
```

## PostGIS SQL Example

Here's the core SQL that generates the hexagon grid:

```sql
WITH bbox_geom AS (
  SELECT ST_MakeEnvelope(-74.0, 40.7, -73.9, 40.8, 4326) as geom
),
bbox_utm AS (
  SELECT
    ST_Transform(geom, 3857) as geom_utm,
    geom as geom_wgs84
  FROM bbox_geom
),
hex_grid AS (
  SELECT
    (ST_HexagonGrid(500, bbox_utm.geom_utm)).geom as hex_geom_utm
  FROM bbox_utm
)
SELECT
  ST_AsGeoJSON(ST_Transform(hex_geom_utm, 4326)) as geojson,
  row_number() OVER () as id
FROM hex_grid
WHERE ST_Intersects(
  hex_geom_utm,
  (SELECT geom_utm FROM bbox_utm)
)
LIMIT 5000;
```

## Performance Considerations

### Backend Optimizations

1. **Request Limiting**: Maximum 5000 hexagons per request
2. **Area Validation**: Rejects requests for areas > 250,000 km²
3. **Coordinate Validation**: Validates lat/lng bounds
4. **Efficient PostGIS**: Uses `ST_HexagonGrid` with proper indexing

### Frontend Optimizations

1. **Debounced Loading**: 300ms delay prevents excessive API calls
2. **Viewport-based Loading**: Only loads visible hexagons
3. **Request Cancellation**: Cancels pending requests when new ones start
4. **Memory Management**: Clears old hexagons before loading new ones
5. **Zoom Restrictions**: Prevents loading at inappropriate zoom levels

## Edge Cases and Solutions

### 1. Large Bounding Boxes

**Problem**: User zooms out too far, requesting millions of hexagons
**Solution**:
- Backend validates area size (max 250,000 km²)
- Returns 400 error with user-friendly message
- Frontend handles error gracefully

### 2. Crossing the International Date Line

**Problem**: Bounding box crosses longitude 180/-180
**Detection**: `min_lon > max_lon`
**Solution**: Currently handled by PostGIS coordinate system transformation

### 3. Polar Regions

**Problem**: Hexagon distortion near poles
**Detection**: Latitude > ±85°
**Note**: Current implementation works with Web Mercator (EPSG:3857) limitations

### 4. Network Issues

**Problem**: API requests fail or timeout
**Solutions**:
- Request cancellation prevents multiple concurrent requests
- Error handling with console logging
- Graceful degradation (no hexagons shown, but map still works)

### 5. Performance on Low-End Devices

**Problem**: Too many hexagons cause rendering slowness
**Solutions**:
- Zoom level restrictions prevent overloading
- Limited hexagon count per request
- Efficient DOM manipulation with LayerGroup

## Configuration Options

### HexagonGrid Constructor Options

```javascript
const options = {
  apiEndpoint: '/api/v1/maps/hexagons',
  style: {
    fillColor: '#3388ff',
    fillOpacity: 0.1,
    color: '#3388ff',
    weight: 1,
    opacity: 0.5
  },
  debounceDelay: 300,    // ms to wait before loading
  maxZoom: 16,           // Don't show beyond this zoom
  minZoom: 8             // Don't show below this zoom
};
```

### Backend Configuration

Edit `app/controllers/api/v1/maps/hexagons_controller.rb`:

```ruby
# Change hexagon size (in meters, center to edge)
hex_size = 500  # For ~1km edge-to-edge

# Change maximum hexagons per request
MAX_HEXAGONS_PER_REQUEST = 5000

# Change area limit (km²)
area_km2 > 250_000
```

## Testing

### Manual Testing Steps

1. **Basic Functionality**:
   - Open map at various zoom levels
   - Toggle "Hexagon Grid" layer on/off
   - Verify hexagons load dynamically when panning

2. **Performance Testing**:
   - Zoom to maximum level and pan rapidly
   - Verify no memory leaks or excessive API calls
   - Test on slow connections

3. **Edge Case Testing**:
   - Zoom out very far (should show error handling)
   - Test near International Date Line
   - Test in polar regions

4. **API Testing**:
   ```bash
   # Test valid request
   curl "http://localhost:3000/api/v1/maps/hexagons?api_key=YOUR_KEY&min_lon=-74&min_lat=40.7&max_lon=-73.9&max_lat=40.8"

   # Test invalid bounding box
   curl "http://localhost:3000/api/v1/maps/hexagons?api_key=YOUR_KEY&min_lon=-180&min_lat=-90&max_lon=180&max_lat=90"
   ```

## Troubleshooting

### Common Issues

1. **Hexagons not appearing**:
   - Check console for API errors
   - Verify API key is valid
   - Check zoom level is within min/max range

2. **Performance issues**:
   - Reduce `MAX_HEXAGONS_PER_REQUEST`
   - Increase `minZoom` to prevent loading at low zoom levels
   - Check for JavaScript errors preventing cleanup

3. **Database errors**:
   - Ensure PostGIS extension is installed
   - Verify `ST_HexagonGrid` function is available (PostGIS 3.1+)
   - Check coordinate system support

### Debug Information

Enable debug logging:

```javascript
// Add to hexagon_grid.js constructor
console.log('HexagonGrid initialized with options:', options);

// Add to loadHexagons method
console.log('Loading hexagons for bounds:', bounds);
```

## Future Enhancements

### Potential Improvements

1. **Caching**: Add Redis caching for frequently requested areas
2. **Clustering**: Group nearby hexagons at low zoom levels
3. **Data Visualization**: Color hexagons based on data (point density, etc.)
4. **Custom Shapes**: Allow other grid patterns (squares, triangles)
5. **Persistent Settings**: Remember user's hexagon visibility preference

### Performance Optimizations

1. **Server-side Caching**: Cache generated hexagon grids
2. **Tile-based Loading**: Load hexagons in tile-like chunks
3. **Progressive Enhancement**: Load lower resolution first, then refine
4. **WebWorker Integration**: Move heavy calculations to background thread

## Dependencies

### Required

- **PostGIS 3.1+**: For `ST_HexagonGrid` function
- **Leaflet**: Frontend mapping library
- **Rails 6+**: Backend framework

### Optional

- **Redis**: For caching (future enhancement)
- **Sidekiq**: For background processing (future enhancement)

## License and Credits

This implementation uses:
- PostGIS for spatial calculations
- Leaflet for map visualization
- Ruby on Rails for API backend

The hexagon grid generation leverages PostGIS's built-in `ST_HexagonGrid` function for optimal performance and accuracy.
