# Tracks Map Layer

This module provides functionality for rendering tracks as a separate layer on Leaflet maps in Dawarich.

## Features

- **Distinct visual styling** - Tracks use brown color to differentiate from blue polylines
- **Interactive hover/click** - Rich popups with track details including distance, duration, elevation
- **Consistent styling** - All tracks use the same brown color for easy identification
- **Layer management** - Integrates with Leaflet layer control
- **Performance optimized** - Uses canvas rendering and efficient event handling

## Usage

### Basic Integration

The tracks layer is automatically integrated into the main maps controller:

```javascript
// Import the tracks module
import { createTracksLayer, updateTracksColors } from "../maps/tracks";

// Create tracks layer
const tracksLayer = createTracksLayer(tracksData, map, userSettings, distanceUnit);

// Add to map
tracksLayer.addTo(map);
```

### Styling

All tracks use a consistent brown color (#8B4513) to ensure they are easily distinguishable from the blue polylines used for regular routes.

### Track Data Format

Tracks expect data in this format:

```javascript
{
  id: 123,
  start_at: "2025-01-15T10:00:00Z",
  end_at: "2025-01-15T11:30:00Z",
  distance: 15000, // meters
  duration: 5400, // seconds
  avg_speed: 25.5, // km/h
  elevation_gain: 200, // meters
  elevation_loss: 150, // meters
  elevation_max: 500, // meters
  elevation_min: 300, // meters
  original_path: "LINESTRING(-74.0060 40.7128, -74.0070 40.7130)", // PostGIS format
  // OR
  coordinates: [[40.7128, -74.0060], [40.7130, -74.0070]], // [lat, lng] array
  // OR
  path: [[40.7128, -74.0060], [40.7130, -74.0070]] // alternative coordinate format
}
```

### Coordinate Parsing

The module automatically handles different coordinate formats:

1. **Array format**: `track.coordinates` or `track.path` as `[[lat, lng], ...]`
2. **PostGIS LineString**: Parses `"LINESTRING(lng lat, lng lat, ...)"` format
3. **Fallback**: Creates simple line from start/end points if available

### API Integration

The tracks layer integrates with these API endpoints:

- **GET `/api/v1/tracks`** - Fetch existing tracks
- **POST `/api/v1/tracks`** - Trigger track generation from points

### Settings Integration

Track settings are integrated into the main map settings panel:

- **Show Tracks** - Toggle track layer visibility
- **Refresh Tracks** - Regenerate tracks from current points

### Layer Control

Tracks appear as "Tracks" in the Leaflet layer control, positioned above regular polylines with z-index 460.

## Visual Features

### Markers

- **Start marker**: 🚀 (rocket emoji)
- **End marker**: 🎯 (target emoji)

### Popup Content

Track popups display:
- Track ID
- Start/end timestamps
- Duration (formatted as days/hours/minutes)
- Total distance
- Average speed
- Elevation statistics (gain/loss/max/min)

### Interaction States

- **Default**: Brown polylines (weight: 4)
- **Hover**: Orange polylines (weight: 6)
- **Clicked**: Red polylines (weight: 8, persistent until clicked elsewhere)

## Performance Considerations

- Uses Leaflet canvas renderer for efficient rendering
- Custom pane (`tracksPane`) with z-index 460
- Efficient coordinate parsing with error handling
- Minimal DOM manipulation during interactions

## Error Handling

- Graceful handling of missing coordinate data
- Console warnings for unparseable track data
- Fallback to empty layer if tracks API unavailable
- Error messages for failed track generation
