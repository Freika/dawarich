# MapLibre Implementation Guide

## Overview

We've successfully implemented MapLibre GL JS as a toggleable alternative to Leaflet in Dawarich. Users can now switch between the two mapping engines using a query parameter or UI toggle button.

## What's Been Implemented

### 1. Package Installation

- **MapLibre GL JS v5.10.0** added to npm dependencies
- Pinned to Rails importmap for asset management
- CSS loaded conditionally based on map engine selection

### 2. MapLibre Controller

Created a new Stimulus controller (`app/javascript/controllers/maplibre_controller.js`) that provides:

#### Core Features Implemented

- ✅ **Map Initialization** - Basic MapLibre map with center/zoom
- ✅ **Navigation Controls** - Pan, zoom, rotate controls
- ✅ **Scale Control** - Metric/Imperial units based on user settings
- ✅ **Geolocate Control** - User location tracking
- ✅ **Fullscreen Control** - Fullscreen map view
- ✅ **Points Display** - All GPS points rendered as circle markers
- ✅ **Popups** - Click markers to view details (timestamp, battery, altitude, speed, country)
- ✅ **Hover Effects** - Cursor changes on point hover
- ✅ **Auto-fit Bounds** - Map automatically fits to show all points
- ✅ **Theme Support** - Dark/light map styles based on user theme

#### Map Styles Available

1. **OSM (OpenStreetMap)** - Raster tiles from OSM
2. **Streets** - Stadia Maps Alidade Smooth style
3. **Satellite** - Esri World Imagery
4. **Dark** - Stadia Maps dark theme
5. **Light** - OpenStreetMap light theme

### 3. Toggle Mechanism

#### Query Parameter Method
```
http://localhost:3000/map?maplibre=true   # Use MapLibre
http://localhost:3000/map?maplibre=false  # Use Leaflet
```

#### UI Toggle Button
- Fixed position button in top-right corner (below navbar)
- Shows "Switch to MapLibre" or "Switch to Leaflet" based on current engine
- Maintains current date range when switching
- Uses DaisyUI button styling for consistency

### 4. Conditional Loading

The implementation conditionally loads CSS and controllers based on the `maplibre` parameter:

**Layout Changes** (`app/views/layouts/map.html.erb`):
- Loads MapLibre CSS when `?maplibre=true`
- Loads Leaflet CSS + Leaflet.draw CSS otherwise

**View Changes** (`app/views/map/index.html.erb`):
- Uses `maplibre` controller when enabled
- Uses `maps` controller otherwise
- Hides fog of war element for MapLibre (not yet implemented)

## File Changes Summary

### New Files
- `app/javascript/controllers/maplibre_controller.js` - MapLibre Stimulus controller

### Modified Files
- `package.json` - Added maplibre-gl dependency
- `config/importmap.rb` - Pinned maplibre-gl package
- `app/views/layouts/map.html.erb` - Conditional CSS loading
- `app/views/map/index.html.erb` - Toggle button and conditional controller

## Current Capabilities

### ✅ Working Features (MapLibre)
- Map rendering with OpenStreetMap tiles
- Point markers (all GPS points)
- Navigation controls (zoom, pan)
- Scale control
- Geolocate control
- Fullscreen control
- Click popups with point details
- Auto-fit to bounds
- Theme-based map styles
- Toggle between engines

### ⏳ Not Yet Implemented (MapLibre)
These Leaflet features need to be ported to MapLibre:

1. **Routes/Polylines** - Speed-colored route rendering
2. **Tracks** - GPS track visualization
3. **Heatmap** - Density visualization (easier in MapLibre - native support!)
4. **Fog of War** - Canvas overlay showing explored areas
5. **Scratch Map** - Visited countries overlay
6. **Areas** - User-defined geographic areas
7. **Visits** - Location visit detection and display
8. **Photos** - Geotagged photo markers
9. **Live Mode** - Real-time GPS streaming
10. **Family Members** - Real-time family location sharing
11. **Location Search** - Search and navigate to locations
12. **Drawing Tools** - Create custom areas
13. **Layer Control** - Show/hide different layers
14. **Settings Panel** - Map configuration UI
15. **Calendar Panel** - Date range selection

## Usage Instructions

### For Users

1. **Default Mode (Leaflet)**:
   - Navigate to `/map` as usual
   - All existing features work normally

2. **MapLibre Mode**:
   - Click "Switch to MapLibre" button in top-right
   - Or add `?maplibre=true` to URL
   - See your GPS points on a modern WebGL-powered map

3. **Switching Back**:
   - Click "Switch to Leaflet" button
   - Or add `?maplibre=false` to URL
   - Return to full-featured Leaflet mode

### For Developers

#### Testing the Implementation

```bash
# Start the Rails server
bundle exec rails server

# Visit the map page
open http://localhost:3000/map

# Test MapLibre mode
open http://localhost:3000/map?maplibre=true
```

#### Adding New MapLibre Features

1. **Add to maplibre_controller.js**:
   ```javascript
   // Example: Adding a new feature
   addNewFeature() {
     // Your MapLibre implementation
   }
   ```

2. **Check data availability**:
   - All data attributes from Leaflet controller are available
   - Access via `this.element.dataset.xxx`

3. **Use MapLibre APIs**:
   - Sources: `this.map.addSource()`
   - Layers: `this.map.addLayer()`
   - Events: `this.map.on()`

## Next Steps

### Phase 1: Core Features (High Priority)
- [ ] Implement polylines/routes with speed colors
- [ ] Add heatmap layer (native MapLibre support)
- [ ] Port track visualization
- [ ] Implement layer control UI

### Phase 2: Advanced Features (Medium Priority)
- [ ] Fog of War custom layer
- [ ] Scratch map (visited countries)
- [ ] Areas and visits
- [ ] Photo markers

### Phase 3: Real-time Features (Low Priority)
- [ ] Live mode integration
- [ ] Family members layer
- [ ] WebSocket updates

### Phase 4: Tools & Interaction (Future)
- [ ] Drawing tools (maplibre-gl-draw)
- [ ] Location search integration
- [ ] Settings panel for MapLibre

## Performance Comparison

### Expected Benefits of MapLibre

1. **Better Performance**:
   - Hardware-accelerated WebGL rendering
   - Smoother with large datasets (10,000+ points)
   - Better mobile performance

2. **Modern Features**:
   - Native vector tile support
   - Built-in heatmap layer
   - 3D terrain support (future)
   - Better style expressions

3. **Active Development**:
   - Regular updates and improvements
   - Growing community
   - Better documentation

### Leaflet Advantages (Why Keep It)

1. **Feature Complete**:
   - All existing features work
   - Extensive plugin ecosystem
   - Mature and stable

2. **Simpler API**:
   - Easier to understand
   - More examples available
   - Faster development

3. **Lower Resource Usage**:
   - Canvas-based rendering
   - Lower GPU requirements
   - Better for older devices

## Architecture Notes

### Controller Inheritance

Both controllers extend `BaseController`:
```javascript
import BaseController from "./base_controller";
export default class extends BaseController {
  // Controller implementation
}
```

### Data Sharing

Both controllers receive identical data attributes:
- `data-api_key` - User API key
- `data-coordinates` - GPS points array
- `data-tracks` - Track data
- `data-user_settings` - User preferences
- `data-features` - Enabled features
- `data-user_theme` - Dark/light theme

### Separation of Concerns

- **Leaflet**: `maps_controller.js` + helper files in `app/javascript/maps/`
- **MapLibre**: `maplibre_controller.js` (self-contained for now)
- **Shared**: View templates detect which to load

## Technical Decisions

### Why Query Parameter?
- Simple to implement
- Easy to share URLs
- No database changes needed
- Can be enhanced with session storage later

### Why Separate Controller?
- Clean separation of concerns
- Easier to develop independently
- No risk of breaking Leaflet functionality
- Can eventually deprecate Leaflet if MapLibre is preferred

### Why Keep Leaflet?
- Zero-risk migration strategy
- Users can choose based on needs
- Fallback for unsupported features
- Plugin ecosystem still valuable

## Known Issues

1. **Family Members Controller**: Expects `window.mapsController` - needs adapter for MapLibre
2. **Points Controller**: May expect Leaflet-specific APIs
3. **Add Visit Controller**: Drawing tools use Leaflet.draw
4. **No Session Persistence**: Toggle preference not saved (yet)

## Configuration

### User Settings (Respected by MapLibre)

```json
{
  "maps": {
    "distance_unit": "km",  // or "mi"
    "url": "custom-tile-server-url"
  },
  "preferred_map_layer": "OSM"  // or "Streets", "Satellite", etc.
}
```

### Feature Flags (Future)

Could add to `features` hash:
```ruby
@features = {
  maplibre_enabled: true,
  maplibre_default: false  # Make MapLibre the default
}
```

## Resources

- [MapLibre GL JS Documentation](https://maplibre.org/maplibre-gl-js/docs/)
- [MapLibre Style Spec](https://maplibre.org/maplibre-style-spec/)
- [MapLibre Examples](https://maplibre.org/maplibre-gl-js/docs/examples/)
- [Migration from Mapbox](https://github.com/maplibre/maplibre-gl-js/blob/main/MIGRATION.md)

## Testing Checklist

Before deploying to production:

- [ ] Test point rendering with small dataset (< 100 points)
- [ ] Test point rendering with large dataset (> 10,000 points)
- [ ] Test on mobile devices
- [ ] Test theme switching (dark/light)
- [ ] Test with different date ranges
- [ ] Verify toggle button works in all scenarios
- [ ] Check browser console for errors
- [ ] Test with different map styles
- [ ] Verify user settings are respected
- [ ] Test fullscreen mode
- [ ] Test geolocate feature

## Support

For issues with the MapLibre implementation:
1. Check browser console for errors
2. Verify MapLibre CSS is loaded
3. Check importmap configuration
4. Test with `?maplibre=false` to confirm Leaflet still works
