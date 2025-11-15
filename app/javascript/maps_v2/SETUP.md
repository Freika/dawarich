# Maps V2 Setup Guide

## Installation

### 1. Install Dependencies

Add MapLibre GL JS to your package.json:

```bash
npm install maplibre-gl@^4.0.0
# or
yarn add maplibre-gl@^4.0.0
```

### 2. Configure Routes

Add the Map V2 route to `config/routes.rb`:

```ruby
# Map V2 - Modern mobile-first implementation
get 'map/v2', to: 'map_v2#index', as: :map_v2
```

### 3. Register Stimulus Controller

The controller should auto-register if using Stimulus autoloading. If not, add to `app/javascript/controllers/index.js`:

```javascript
import MapV2Controller from "./map_v2_controller"
application.register("map-v2", MapV2Controller)
```

### 4. Add MapLibre CSS

The view template already includes the MapLibre CSS CDN link. For production, consider adding it to your asset pipeline:

```html
<link href="https://unpkg.com/maplibre-gl@4.0.0/dist/maplibre-gl.css" rel="stylesheet">
```

Or via npm/importmap:

```javascript
import 'maplibre-gl/dist/maplibre-gl.css'
```

## Usage

### Basic Usage

Visit `/map/v2` in your browser to see the new map interface.

### URL Parameters

The map supports the same URL parameters as V1:

- `start_at` - Start date/time (ISO 8601 format)
- `end_at` - End date/time (ISO 8601 format)
- `tracks_debug=true` - Show tracks/routes (experimental)

Example:
```
/map/v2?start_at=2024-01-01T00:00&end_at=2024-01-31T23:59
```

## Features

### Mobile Features

- **Bottom Sheet**: Swipe up/down to access layer controls
- **Gesture Controls**:
  - Pinch to zoom
  - Two-finger drag to pan
  - Long press for context actions
- **Touch-Optimized**: Large buttons and controls
- **Responsive**: Adapts to screen size and orientation

### Desktop Features

- **Sidebar**: Persistent controls panel
- **Keyboard Shortcuts**: (Coming soon)
- **Multi-panel Layout**: (Coming soon)

## Architecture

### Core Components

1. **MapEngine** (`core/MapEngine.js`)
   - MapLibre GL JS wrapper
   - Handles map initialization and basic operations
   - Manages sources and layers

2. **StateManager** (`core/StateManager.js`)
   - Centralized state management
   - Persistent storage
   - Reactive updates

3. **EventBus** (`core/EventBus.js`)
   - Component communication
   - Pub/sub system
   - Decoupled architecture

4. **LayerManager** (`layers/LayerManager.js`)
   - Layer lifecycle management
   - GeoJSON conversion
   - Click handlers and popups

5. **BottomSheet** (`components/BottomSheet.js`)
   - Mobile-first UI component
   - Gesture-based interaction
   - Snap points support

### Data Flow

```
User Action
    ↓
Stimulus Controller
    ↓
State Manager (updates state)
    ↓
Event Bus (emits events)
    ↓
Components (react to events)
    ↓
Map Engine (updates map)
```

## Customization

### Adding Custom Layers

```javascript
// In your controller or component
this.layerManager.registerLayer('custom-layer', {
  name: 'My Custom Layer',
  type: 'circle',
  source: 'custom-source',
  paint: {
    'circle-radius': 6,
    'circle-color': '#ff0000'
  }
})

// Add the layer
this.layerManager.addCustomLayer(customData)
```

### Changing Theme

```javascript
// Programmatically change theme
this.mapEngine.setStyle('dark') // or 'light'

// Via state manager
this.stateManager.set('ui.theme', 'dark')
```

### Custom Bottom Sheet Content

```javascript
import { BottomSheet } from '../maps_v2/components/BottomSheet'

const customContent = document.createElement('div')
customContent.innerHTML = '<h2>Custom Content</h2>'

const sheet = new BottomSheet({
  content: customContent,
  snapPoints: [0.1, 0.5, 0.9],
  initialSnap: 0.5
})
```

## Performance Optimization

### Point Clustering

Points are automatically clustered at lower zoom levels to improve performance:

```javascript
// Clustering is enabled by default for points
// Adjust cluster settings:
this.mapEngine.addSource('points-source', geojson, {
  cluster: true,
  clusterMaxZoom: 14,  // Max zoom to cluster points
  clusterRadius: 50     // Radius of cluster in pixels
})
```

### Layer Visibility

Only load layers when needed:

```javascript
// Lazy load heatmap
eventBus.on(Events.LAYER_ADD, (data) => {
  if (data.layerId === 'heatmap') {
    this.layerManager.addHeatmapLayer()
  }
})
```

## Debugging

### Enable Debug Mode

```javascript
// In browser console
localStorage.setItem('mapV2Debug', 'true')
location.reload()
```

### Event Logging

```javascript
// Log all events
eventBus.on('*', (event, data) => {
  console.log(`[Event] ${event}:`, data)
})
```

### State Inspector

```javascript
// In browser console
console.log(this.stateManager.export())
```

## Troubleshooting

### Map Not Loading

1. Check browser console for errors
2. Verify MapLibre GL JS is loaded: `console.log(maplibregl)`
3. Check if container element exists: `document.querySelector('[data-controller="map-v2"]')`

### Bottom Sheet Not Working

1. Ensure touch events are not prevented by other elements
2. Check z-index of bottom sheet (should be 999)
3. Verify snap points are between 0 and 1

### Performance Issues

1. Reduce point count with clustering
2. Limit date range to reduce data
3. Disable unused layers
4. Use simplified rendering mode

## Migration from V1

### Differences from V1

| Feature | V1 (Leaflet) | V2 (MapLibre) |
|---------|-------------|---------------|
| Base Library | Leaflet.js | MapLibre GL JS |
| Rendering | Canvas | WebGL |
| Mobile UI | Basic | Bottom Sheet |
| State Management | None | Centralized |
| Event System | Direct calls | Event Bus |
| Layer Management | Manual | Managed |

### Compatibility

V2 is designed to coexist with V1. Both can be used simultaneously:

- V1: `/map`
- V2: `/map/v2`

### Data Format

Both versions use the same backend API and data format, making migration straightforward.

## Browser Support

- ✅ Chrome 90+
- ✅ Firefox 88+
- ✅ Safari 14+
- ✅ Edge 90+
- ✅ iOS Safari 14+
- ✅ Chrome Mobile 90+

WebGL required for MapLibre GL JS.

## Contributing

### Code Style

- Use ES6+ features
- Follow existing patterns
- Add JSDoc comments
- Keep components focused

### Testing

```bash
# Run tests (when available)
npm test

# Lint code
npm run lint
```

## Resources

- [MapLibre GL JS Documentation](https://maplibre.org/maplibre-gl-js/docs/)
- [GeoJSON Specification](https://geojson.org/)
- [Stimulus Handbook](https://stimulus.hotwired.dev/)
