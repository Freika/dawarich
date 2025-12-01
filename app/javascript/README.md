# Dawarich JavaScript Architecture

This document provides a comprehensive guide to the JavaScript architecture used in the Dawarich application, with a focus on the Maps (MapLibre) implementation.

## Table of Contents

- [Overview](#overview)
- [Technology Stack](#technology-stack)
- [Architecture Patterns](#architecture-patterns)
- [Directory Structure](#directory-structure)
- [Core Concepts](#core-concepts)
- [Maps (MapLibre) Architecture](#maps-v2-architecture)
- [Creating New Features](#creating-new-features)
- [Best Practices](#best-practices)

## Overview

Dawarich uses a modern JavaScript architecture built on **Hotwire (Turbo + Stimulus)** for page interactions and **MapLibre GL JS** for map rendering. The Maps (MapLibre) implementation follows object-oriented principles with clear separation of concerns.

## Technology Stack

- **Stimulus** - Modest JavaScript framework for sprinkles of interactivity
- **Turbo Rails** - SPA-like page navigation without building an SPA
- **MapLibre GL JS** - Open-source map rendering engine
- **ES6 Modules** - Modern JavaScript module system
- **Tailwind CSS + DaisyUI** - Utility-first CSS framework

## Architecture Patterns

### 1. Stimulus Controllers

**Purpose:** Connect DOM elements to JavaScript behavior

**Location:** `app/javascript/controllers/`

**Pattern:**
```javascript
import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  static targets = ['element']
  static values = { apiKey: String }

  connect() {
    // Initialize when element appears in DOM
  }

  disconnect() {
    // Cleanup when element is removed
  }
}
```

**Key Principles:**
- Controllers should be stateless when possible
- Use `targets` for DOM element references
- Use `values` for passing data from HTML
- Always cleanup in `disconnect()`

### 2. Service Classes

**Purpose:** Encapsulate business logic and API communication

**Location:** `app/javascript/maps_maplibre/services/`

**Pattern:**
```javascript
export class ApiClient {
  constructor(apiKey) {
    this.apiKey = apiKey
  }

  async fetchData() {
    const response = await fetch(url, {
      headers: this.getHeaders()
    })
    return response.json()
  }
}
```

**Key Principles:**
- Single responsibility - one service per concern
- Consistent error handling
- Return promises for async operations
- Use constructor injection for dependencies

### 3. Layer Classes (Map Layers)

**Purpose:** Manage map visualization layers

**Location:** `app/javascript/maps_maplibre/layers/`

**Pattern:**
```javascript
import { BaseLayer } from './base_layer'

export class CustomLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'custom', ...options })
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data
    }
  }

  getLayerConfigs() {
    return [{
      id: this.id,
      type: 'circle',
      source: this.sourceId,
      paint: { /* ... */ }
    }]
  }
}
```

**Key Principles:**
- All layers extend `BaseLayer`
- Implement `getSourceConfig()` and `getLayerConfigs()`
- Store data in `this.data`
- Use `this.visible` for visibility state
- Inherit common methods: `add()`, `update()`, `show()`, `hide()`, `toggle()`

### 4. Utility Modules

**Purpose:** Provide reusable helper functions

**Location:** `app/javascript/maps_maplibre/utils/`

**Pattern:**
```javascript
export class UtilityClass {
  static helperMethod(param) {
    // Static methods for stateless utilities
  }
}

// Or singleton pattern
export const utilityInstance = new UtilityClass()
```

### 5. Component Classes

**Purpose:** Reusable UI components

**Location:** `app/javascript/maps_maplibre/components/`

**Pattern:**
```javascript
export class PopupFactory {
  static createPopup(data) {
    return `<div>${data.name}</div>`
  }
}
```

## Directory Structure

```
app/javascript/
├── application.js              # Entry point
├── controllers/                # Stimulus controllers
│   ├── maps/maplibre_controller.js   # Main map controller
│   ├── maps_maplibre/                # Controller modules
│   │   ├── layer_manager.js    # Layer lifecycle management
│   │   ├── data_loader.js      # API data fetching
│   │   ├── event_handlers.js   # Map event handling
│   │   ├── filter_manager.js   # Data filtering
│   │   └── date_manager.js     # Date range management
│   └── ...                     # Other controllers
├── maps_maplibre/                    # Maps (MapLibre) implementation
│   ├── layers/                 # Map layer classes
│   │   ├── base_layer.js       # Abstract base class
│   │   ├── points_layer.js     # Point markers
│   │   ├── routes_layer.js     # Route lines
│   │   ├── heatmap_layer.js    # Heatmap visualization
│   │   ├── visits_layer.js     # Visit markers
│   │   ├── photos_layer.js     # Photo markers
│   │   ├── places_layer.js     # Places markers
│   │   ├── areas_layer.js      # User-defined areas
│   │   ├── fog_layer.js        # Fog of war overlay
│   │   └── scratch_layer.js    # Scratch map
│   ├── services/               # API and external services
│   │   ├── api_client.js       # REST API wrapper
│   │   └── location_search_service.js
│   ├── utils/                  # Helper utilities
│   │   ├── settings_manager.js # User preferences
│   │   ├── geojson_transformers.js
│   │   ├── performance_monitor.js
│   │   ├── lazy_loader.js      # Code splitting
│   │   └── ...
│   ├── components/             # Reusable UI components
│   │   ├── popup_factory.js    # Map popup generator
│   │   ├── toast.js            # Toast notifications
│   │   └── ...
│   └── channels/               # ActionCable channels
│       └── map_channel.js      # Real-time updates
└── maps/                       # Legacy Maps V1 (being phased out)
```

## Core Concepts

### Manager Pattern

The Maps (MapLibre) controller delegates responsibilities to specialized managers:

1. **LayerManager** - Layer lifecycle (add/remove/toggle/update)
2. **DataLoader** - API data fetching and transformation
3. **EventHandlers** - Map interaction events
4. **FilterManager** - Data filtering and searching
5. **DateManager** - Date range calculations
6. **SettingsManager** - User preferences persistence

**Benefits:**
- Single Responsibility Principle
- Easier testing
- Improved code organization
- Better reusability

### Data Flow

```
User Action
    ↓
Stimulus Controller Method
    ↓
Manager (e.g., DataLoader)
    ↓
Service (e.g., ApiClient)
    ↓
API Endpoint
    ↓
Transform to GeoJSON
    ↓
Update Layer
    ↓
MapLibre Renders
```

### State Management

**Settings Persistence:**
- Primary: Backend API (`/api/v1/settings`)
- Fallback: localStorage
- Sync on initialization
- Save on every change (debounced)

**Layer State:**
- Stored in layer instances (`this.visible`, `this.data`)
- Synced with SettingsManager
- Persisted across sessions

### Event System

**Custom Events:**
```javascript
// Dispatch
document.dispatchEvent(new CustomEvent('visit:created', {
  detail: { visitId: 123 }
}))

// Listen
document.addEventListener('visit:created', (event) => {
  console.log(event.detail.visitId)
})
```

**Map Events:**
```javascript
map.on('click', 'layer-id', (e) => {
  const feature = e.features[0]
  // Handle click
})
```

## Maps (MapLibre) Architecture

### Layer Hierarchy

Layers are rendered in specific order (bottom to top):

1. **Scratch Layer** - Visited countries/regions overlay
2. **Heatmap Layer** - Point density visualization
3. **Areas Layer** - User-defined circular areas
4. **Tracks Layer** - Imported GPS tracks
5. **Routes Layer** - Generated routes from points
6. **Visits Layer** - Detected visits to places
7. **Places Layer** - Named locations
8. **Photos Layer** - Photos with geolocation
9. **Family Layer** - Real-time family member locations
10. **Points Layer** - Individual location points
11. **Fog Layer** - Canvas overlay showing unexplored areas

### BaseLayer Pattern

All layers extend `BaseLayer` which provides:

**Methods:**
- `add(data)` - Add layer to map
- `update(data)` - Update layer data
- `remove()` - Remove layer from map
- `show()` / `hide()` - Toggle visibility
- `toggle(visible)` - Set visibility state

**Abstract Methods (must implement):**
- `getSourceConfig()` - MapLibre source configuration
- `getLayerConfigs()` - Array of MapLibre layer configurations

**Example Implementation:**
```javascript
export class PointsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'points', ...options })
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || { type: 'FeatureCollection', features: [] }
    }
  }

  getLayerConfigs() {
    return [{
      id: 'points',
      type: 'circle',
      source: this.sourceId,
      paint: {
        'circle-radius': 4,
        'circle-color': '#3b82f6'
      }
    }]
  }
}
```

### Lazy Loading

Heavy layers are lazy-loaded to reduce initial bundle size:

```javascript
// In lazy_loader.js
const paths = {
  'fog': () => import('../layers/fog_layer.js'),
  'scratch': () => import('../layers/scratch_layer.js')
}

// Usage
const ScratchLayer = await lazyLoader.loadLayer('scratch')
const layer = new ScratchLayer(map, options)
```

**When to use:**
- Large dependencies (e.g., canvas-based rendering)
- Rarely-used features
- Heavy computations

### GeoJSON Transformations

All data is transformed to GeoJSON before rendering:

```javascript
// Points
{
  type: 'FeatureCollection',
  features: [{
    type: 'Feature',
    geometry: {
      type: 'Point',
      coordinates: [longitude, latitude]
    },
    properties: {
      id: 1,
      timestamp: '2024-01-01T12:00:00Z',
      // ... other properties
    }
  }]
}
```

**Key Functions:**
- `pointsToGeoJSON(points)` - Convert points array
- `visitsToGeoJSON(visits)` - Convert visits
- `photosToGeoJSON(photos)` - Convert photos
- `placesToGeoJSON(places)` - Convert places
- `areasToGeoJSON(areas)` - Convert circular areas to polygons

## Creating New Features

### Adding a New Layer

1. **Create layer class** in `app/javascript/maps_maplibre/layers/`:

```javascript
import { BaseLayer } from './base_layer'

export class NewLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'new-layer', ...options })
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || { type: 'FeatureCollection', features: [] }
    }
  }

  getLayerConfigs() {
    return [{
      id: this.id,
      type: 'symbol', // or 'circle', 'line', 'fill', 'heatmap'
      source: this.sourceId,
      paint: { /* styling */ },
      layout: { /* layout */ }
    }]
  }
}
```

2. **Register in LayerManager** (`controllers/maps_maplibre/layer_manager.js`):

```javascript
import { NewLayer } from 'maps_maplibre/layers/new_layer'

// In addAllLayers method
_addNewLayer(dataGeoJSON) {
  if (!this.layers.newLayer) {
    this.layers.newLayer = new NewLayer(this.map, {
      visible: this.settings.newLayerEnabled || false
    })
    this.layers.newLayer.add(dataGeoJSON)
  } else {
    this.layers.newLayer.update(dataGeoJSON)
  }
}
```

3. **Add to settings** (`utils/settings_manager.js`):

```javascript
const DEFAULT_SETTINGS = {
  // ...
  newLayerEnabled: false
}

const LAYER_NAME_MAP = {
  // ...
  'New Layer': 'newLayerEnabled'
}
```

4. **Add UI controls** in view template.

### Adding a New API Endpoint

1. **Add method to ApiClient** (`services/api_client.js`):

```javascript
async fetchNewData({ param1, param2 }) {
  const params = new URLSearchParams({ param1, param2 })

  const response = await fetch(`${this.baseURL}/new-endpoint?${params}`, {
    headers: this.getHeaders()
  })

  if (!response.ok) {
    throw new Error(`Failed to fetch: ${response.statusText}`)
  }

  return response.json()
}
```

2. **Add transformation** in DataLoader:

```javascript
newDataToGeoJSON(data) {
  return {
    type: 'FeatureCollection',
    features: data.map(item => ({
      type: 'Feature',
      geometry: { /* ... */ },
      properties: { /* ... */ }
    }))
  }
}
```

3. **Use in controller:**

```javascript
const data = await this.api.fetchNewData({ param1, param2 })
const geojson = this.dataLoader.newDataToGeoJSON(data)
this.layerManager.updateLayer('new-layer', geojson)
```

### Adding a New Utility

1. **Create utility file** in `utils/`:

```javascript
export class NewUtility {
  static calculate(input) {
    // Pure function - no side effects
    return result
  }
}

// Or singleton for stateful utilities
class NewManager {
  constructor() {
    this.state = {}
  }

  doSomething() {
    // Stateful operation
  }
}

export const newManager = new NewManager()
```

2. **Import and use:**

```javascript
import { NewUtility } from 'maps_maplibre/utils/new_utility'

const result = NewUtility.calculate(input)
```

## Best Practices

### Code Style

1. **Use ES6+ features:**
   - Arrow functions
   - Template literals
   - Destructuring
   - Async/await
   - Classes

2. **Naming conventions:**
   - Classes: `PascalCase`
   - Methods/variables: `camelCase`
   - Constants: `UPPER_SNAKE_CASE`
   - Files: `snake_case.js`

3. **Always use semicolons** for statement termination

4. **Prefer `const` over `let`**, avoid `var`

### Performance

1. **Lazy load heavy features:**
   ```javascript
   const Layer = await lazyLoader.loadLayer('name')
   ```

2. **Debounce frequent operations:**
   ```javascript
   let timeout
   function onInput(e) {
     clearTimeout(timeout)
     timeout = setTimeout(() => actualWork(e), 300)
   }
   ```

3. **Use performance monitoring:**
   ```javascript
   performanceMonitor.mark('operation')
   // ... do work
   performanceMonitor.measure('operation')
   ```

4. **Minimize DOM manipulations** - batch updates when possible

### Error Handling

1. **Always handle promise rejections:**
   ```javascript
   try {
     const data = await fetchData()
   } catch (error) {
     console.error('Failed:', error)
     Toast.error('Operation failed')
   }
   ```

2. **Provide user feedback:**
   ```javascript
   Toast.success('Data loaded')
   Toast.error('Failed to load data')
   Toast.info('Click map to add point')
   ```

3. **Log errors for debugging:**
   ```javascript
   console.error('[Component] Error details:', error)
   ```

### Memory Management

1. **Always cleanup in disconnect():**
   ```javascript
   disconnect() {
     this.searchManager?.destroy()
     this.cleanup.cleanup()
     this.map?.remove()
   }
   ```

2. **Use CleanupHelper for event listeners:**
   ```javascript
   this.cleanup = new CleanupHelper()
   this.cleanup.addEventListener(element, 'click', handler)

   // In disconnect():
   this.cleanup.cleanup() // Removes all listeners
   ```

3. **Remove map layers and sources:**
   ```javascript
   remove() {
     this.getLayerIds().forEach(id => {
       if (this.map.getLayer(id)) {
         this.map.removeLayer(id)
       }
     })
     if (this.map.getSource(this.sourceId)) {
       this.map.removeSource(this.sourceId)
     }
   }
   ```

### Testing Considerations

1. **Keep methods small and focused** - easier to test
2. **Avoid tight coupling** - use dependency injection
3. **Separate pure functions** from side effects
4. **Use static methods** for stateless utilities

### State Management

1. **Single source of truth:**
   - Settings: `SettingsManager`
   - Layer data: Layer instances
   - UI state: Controller properties

2. **Sync state with backend:**
   ```javascript
   SettingsManager.updateSetting('key', value)
   // Saves to both localStorage and backend
   ```

3. **Restore state on load:**
   ```javascript
   async connect() {
     this.settings = await SettingsManager.sync()
     this.syncToggleStates()
   }
   ```

### Documentation

1. **Add JSDoc comments for public APIs:**
   ```javascript
   /**
    * Fetch all points for date range
    * @param {Object} options - { start_at, end_at, onProgress }
    * @returns {Promise<Array>} All points
    */
   async fetchAllPoints({ start_at, end_at, onProgress }) {
     // ...
   }
   ```

2. **Document complex logic with inline comments**

3. **Keep this README updated** when adding major features

### Code Organization

1. **One class per file** - easier to find and maintain
2. **Group related functionality** in directories
3. **Use index files** for barrel exports when needed
4. **Avoid circular dependencies** - use dependency injection

### Migration from Maps V1 to V2

When updating features, follow this pattern:

1. **Keep V1 working** - V2 is opt-in
2. **Share utilities** where possible (e.g., color calculations)
3. **Use same API endpoints** - maintain compatibility
4. **Document differences** in code comments

---

## Examples

### Complete Layer Implementation

See `app/javascript/maps_maplibre/layers/heatmap_layer.js` for a simple example.

### Complete Utility Implementation

See `app/javascript/maps_maplibre/utils/settings_manager.js` for state management.

### Complete Service Implementation

See `app/javascript/maps_maplibre/services/api_client.js` for API communication.

### Complete Controller Implementation

See `app/javascript/controllers/maps/maplibre_controller.js` for orchestration.

---

**Questions or need help?** Check the existing code for patterns or ask in Discord: https://discord.gg/pHsBjpt5J8
