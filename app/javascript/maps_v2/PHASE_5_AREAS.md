# Phase 5: Areas + Drawing Tools

**Timeline**: Week 5
**Goal**: Add area management and drawing tools
**Dependencies**: Phases 1-4 complete
**Status**: Ready for implementation

## 🎯 Phase Objectives

Build on Phases 1-4 by adding:
- ✅ Areas layer (user-defined regions)
- ✅ Rectangle selection tool (click and drag)
- ✅ Area drawing tool (create circular areas)
- ✅ Area management UI (create/edit/delete)
- ✅ Tracks layer
- ✅ Area statistics
- ✅ E2E tests

**Deploy Decision**: Users can create and manage custom geographic areas.

---

## 📋 Features Checklist

- [ ] Areas layer showing user-defined areas
- [ ] Rectangle selection (draw box on map)
- [ ] Area drawer (click to place, drag for radius)
- [ ] Tracks layer (saved routes)
- [ ] Area statistics (visits count, time spent)
- [ ] Edit area properties
- [ ] Delete areas
- [ ] E2E tests passing

---

## 🏗️ New Files (Phase 5)

```
app/javascript/maps_v2/
├── layers/
│   ├── areas_layer.js                 # NEW: User areas
│   └── tracks_layer.js                # NEW: Saved tracks
├── controllers/
│   ├── area_selector_controller.js    # NEW: Rectangle selection
│   └── area_drawer_controller.js      # NEW: Draw circles
└── utils/
    └── geometry.js                    # NEW: Geo calculations

e2e/v2/
└── phase-5-areas.spec.ts              # NEW: E2E tests
```

---

## 5.1 Areas Layer

Display user-defined areas.

**File**: `app/javascript/maps_v2/layers/areas_layer.js`

```javascript
import { BaseLayer } from './base_layer'

/**
 * Areas layer for user-defined regions
 */
export class AreasLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'areas', ...options })
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || {
        type: 'FeatureCollection',
        features: []
      }
    }
  }

  getLayerConfigs() {
    return [
      // Area fills
      {
        id: `${this.id}-fill`,
        type: 'fill',
        source: this.sourceId,
        paint: {
          'fill-color': ['get', 'color'],
          'fill-opacity': 0.2
        }
      },

      // Area outlines
      {
        id: `${this.id}-outline`,
        type: 'line',
        source: this.sourceId,
        paint: {
          'line-color': ['get', 'color'],
          'line-width': 2
        }
      },

      // Area labels
      {
        id: `${this.id}-labels`,
        type: 'symbol',
        source: this.sourceId,
        layout: {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
          'text-size': 14
        },
        paint: {
          'text-color': '#111827',
          'text-halo-color': '#ffffff',
          'text-halo-width': 2
        }
      }
    ]
  }

  getLayerIds() {
    return [`${this.id}-fill`, `${this.id}-outline`, `${this.id}-labels`]
  }
}
```

---

## 5.2 Tracks Layer

**File**: `app/javascript/maps_v2/layers/tracks_layer.js`

```javascript
import { BaseLayer } from './base_layer'

/**
 * Tracks layer for saved routes
 */
export class TracksLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'tracks', ...options })
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || {
        type: 'FeatureCollection',
        features: []
      }
    }
  }

  getLayerConfigs() {
    return [
      {
        id: this.id,
        type: 'line',
        source: this.sourceId,
        layout: {
          'line-join': 'round',
          'line-cap': 'round'
        },
        paint: {
          'line-color': ['get', 'color'],
          'line-width': 4,
          'line-opacity': 0.7
        }
      }
    ]
  }
}
```

---

## 5.3 Geometry Utilities

**File**: `app/javascript/maps_v2/utils/geometry.js`

```javascript
/**
 * Calculate distance between two points in meters
 * @param {Array} point1 - [lng, lat]
 * @param {Array} point2 - [lng, lat]
 * @returns {number} Distance in meters
 */
export function calculateDistance(point1, point2) {
  const [lng1, lat1] = point1
  const [lng2, lat2] = point2

  const R = 6371000 // Earth radius in meters
  const φ1 = lat1 * Math.PI / 180
  const φ2 = lat2 * Math.PI / 180
  const Δφ = (lat2 - lat1) * Math.PI / 180
  const Δλ = (lng2 - lng1) * Math.PI / 180

  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
            Math.cos(φ1) * Math.cos(φ2) *
            Math.sin(Δλ / 2) * Math.sin(Δλ / 2)

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

  return R * c
}

/**
 * Create circle polygon
 * @param {Array} center - [lng, lat]
 * @param {number} radiusInMeters
 * @param {number} points - Number of points in polygon
 * @returns {Array} Coordinates array
 */
export function createCircle(center, radiusInMeters, points = 64) {
  const [lng, lat] = center
  const coords = []

  const distanceX = radiusInMeters / (111320 * Math.cos(lat * Math.PI / 180))
  const distanceY = radiusInMeters / 110540

  for (let i = 0; i < points; i++) {
    const theta = (i / points) * (2 * Math.PI)
    const x = distanceX * Math.cos(theta)
    const y = distanceY * Math.sin(theta)
    coords.push([lng + x, lat + y])
  }

  coords.push(coords[0]) // Close the circle

  return coords
}

/**
 * Create rectangle from bounds
 * @param {Object} bounds - { minLng, minLat, maxLng, maxLat }
 * @returns {Array} Coordinates array
 */
export function createRectangle(bounds) {
  const { minLng, minLat, maxLng, maxLat } = bounds

  return [
    [
      [minLng, minLat],
      [maxLng, minLat],
      [maxLng, maxLat],
      [minLng, maxLat],
      [minLng, minLat]
    ]
  ]
}
```

---

## 5.4 Area Selector Controller

Rectangle selection tool.

**File**: `app/javascript/maps_v2/controllers/area_selector_controller.js`

```javascript
import { Controller } from '@hotwired/stimulus'
import { createRectangle } from '../utils/geometry'

/**
 * Area selector controller
 * Draw rectangle selection on map
 */
export default class extends Controller {
  static outlets = ['map']

  connect() {
    this.isSelecting = false
    this.startPoint = null
    this.currentPoint = null
  }

  /**
   * Start rectangle selection mode
   */
  startSelection() {
    this.isSelecting = true
    this.mapOutlet.map.getCanvas().style.cursor = 'crosshair'

    // Add temporary layer for selection
    if (!this.mapOutlet.map.getSource('selection-source')) {
      this.mapOutlet.map.addSource('selection-source', {
        type: 'geojson',
        data: { type: 'FeatureCollection', features: [] }
      })

      this.mapOutlet.map.addLayer({
        id: 'selection-fill',
        type: 'fill',
        source: 'selection-source',
        paint: {
          'fill-color': '#3b82f6',
          'fill-opacity': 0.2
        }
      })

      this.mapOutlet.map.addLayer({
        id: 'selection-outline',
        type: 'line',
        source: 'selection-source',
        paint: {
          'line-color': '#3b82f6',
          'line-width': 2,
          'line-dasharray': [2, 2]
        }
      })
    }

    // Add event listeners
    this.mapOutlet.map.on('mousedown', this.onMouseDown)
    this.mapOutlet.map.on('mousemove', this.onMouseMove)
    this.mapOutlet.map.on('mouseup', this.onMouseUp)
  }

  /**
   * Cancel selection mode
   */
  cancelSelection() {
    this.isSelecting = false
    this.startPoint = null
    this.currentPoint = null
    this.mapOutlet.map.getCanvas().style.cursor = ''

    // Clear selection
    const source = this.mapOutlet.map.getSource('selection-source')
    if (source) {
      source.setData({ type: 'FeatureCollection', features: [] })
    }

    // Remove event listeners
    this.mapOutlet.map.off('mousedown', this.onMouseDown)
    this.mapOutlet.map.off('mousemove', this.onMouseMove)
    this.mapOutlet.map.off('mouseup', this.onMouseUp)
  }

  /**
   * Mouse down handler
   */
  onMouseDown = (e) => {
    if (!this.isSelecting) return

    this.startPoint = [e.lngLat.lng, e.lngLat.lat]
    this.mapOutlet.map.dragPan.disable()
  }

  /**
   * Mouse move handler
   */
  onMouseMove = (e) => {
    if (!this.isSelecting || !this.startPoint) return

    this.currentPoint = [e.lngLat.lng, e.lngLat.lat]
    this.updateSelection()
  }

  /**
   * Mouse up handler
   */
  onMouseUp = (e) => {
    if (!this.isSelecting || !this.startPoint) return

    this.currentPoint = [e.lngLat.lng, e.lngLat.lat]
    this.mapOutlet.map.dragPan.enable()

    // Emit selection event
    const bounds = this.getSelectionBounds()
    this.dispatch('selected', { detail: { bounds } })

    this.cancelSelection()
  }

  /**
   * Update selection visualization
   */
  updateSelection() {
    if (!this.startPoint || !this.currentPoint) return

    const bounds = this.getSelectionBounds()
    const rectangle = createRectangle(bounds)

    const source = this.mapOutlet.map.getSource('selection-source')
    if (source) {
      source.setData({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          geometry: {
            type: 'Polygon',
            coordinates: rectangle
          }
        }]
      })
    }
  }

  /**
   * Get selection bounds
   */
  getSelectionBounds() {
    return {
      minLng: Math.min(this.startPoint[0], this.currentPoint[0]),
      minLat: Math.min(this.startPoint[1], this.currentPoint[1]),
      maxLng: Math.max(this.startPoint[0], this.currentPoint[0]),
      maxLat: Math.max(this.startPoint[1], this.currentPoint[1])
    }
  }
}
```

---

## 5.5 Area Drawer Controller

Draw circular areas.

**File**: `app/javascript/maps_v2/controllers/area_drawer_controller.js`

```javascript
import { Controller } from '@hotwired/stimulus'
import { createCircle, calculateDistance } from '../utils/geometry'

/**
 * Area drawer controller
 * Draw circular areas on map
 */
export default class extends Controller {
  static outlets = ['map']

  connect() {
    this.isDrawing = false
    this.center = null
    this.radius = 0
  }

  /**
   * Start drawing mode
   */
  startDrawing() {
    this.isDrawing = true
    this.mapOutlet.map.getCanvas().style.cursor = 'crosshair'

    // Add temporary layer
    if (!this.mapOutlet.map.getSource('draw-source')) {
      this.mapOutlet.map.addSource('draw-source', {
        type: 'geojson',
        data: { type: 'FeatureCollection', features: [] }
      })

      this.mapOutlet.map.addLayer({
        id: 'draw-fill',
        type: 'fill',
        source: 'draw-source',
        paint: {
          'fill-color': '#22c55e',
          'fill-opacity': 0.2
        }
      })

      this.mapOutlet.map.addLayer({
        id: 'draw-outline',
        type: 'line',
        source: 'draw-source',
        paint: {
          'line-color': '#22c55e',
          'line-width': 2
        }
      })
    }

    // Add event listeners
    this.mapOutlet.map.on('click', this.onClick)
    this.mapOutlet.map.on('mousemove', this.onMouseMove)
  }

  /**
   * Cancel drawing mode
   */
  cancelDrawing() {
    this.isDrawing = false
    this.center = null
    this.radius = 0
    this.mapOutlet.map.getCanvas().style.cursor = ''

    // Clear drawing
    const source = this.mapOutlet.map.getSource('draw-source')
    if (source) {
      source.setData({ type: 'FeatureCollection', features: [] })
    }

    // Remove event listeners
    this.mapOutlet.map.off('click', this.onClick)
    this.mapOutlet.map.off('mousemove', this.onMouseMove)
  }

  /**
   * Click handler
   */
  onClick = (e) => {
    if (!this.isDrawing) return

    if (!this.center) {
      // First click - set center
      this.center = [e.lngLat.lng, e.lngLat.lat]
    } else {
      // Second click - finish drawing
      const area = {
        center: this.center,
        radius: this.radius
      }

      this.dispatch('drawn', { detail: { area } })
      this.cancelDrawing()
    }
  }

  /**
   * Mouse move handler
   */
  onMouseMove = (e) => {
    if (!this.isDrawing || !this.center) return

    const currentPoint = [e.lngLat.lng, e.lngLat.lat]
    this.radius = calculateDistance(this.center, currentPoint)

    this.updateDrawing()
  }

  /**
   * Update drawing visualization
   */
  updateDrawing() {
    if (!this.center || this.radius === 0) return

    const coordinates = createCircle(this.center, this.radius)

    const source = this.mapOutlet.map.getSource('draw-source')
    if (source) {
      source.setData({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          geometry: {
            type: 'Polygon',
            coordinates: [coordinates]
          }
        }]
      })
    }
  }
}
```

---

## 5.6 Update Map Controller

Add areas and tracks layers.

**File**: `app/javascript/maps_v2/controllers/map_controller.js` (add to loadMapData)

```javascript
// Add imports
import { AreasLayer } from '../layers/areas_layer'
import { TracksLayer } from '../layers/tracks_layer'

// In loadMapData(), add:

// Load areas
const areas = await this.api.fetchAreas()
const areasGeoJSON = this.areasToGeoJSON(areas)

if (!this.areasLayer) {
  this.areasLayer = new AreasLayer(this.map, { visible: false })

  if (this.map.loaded()) {
    this.areasLayer.add(areasGeoJSON)
  } else {
    this.map.on('load', () => {
      this.areasLayer.add(areasGeoJSON)
    })
  }
} else {
  this.areasLayer.update(areasGeoJSON)
}

// Load tracks
const tracks = await this.api.fetchTracks()
const tracksGeoJSON = this.tracksToGeoJSON(tracks)

if (!this.tracksLayer) {
  this.tracksLayer = new TracksLayer(this.map, { visible: false })

  if (this.map.loaded()) {
    this.tracksLayer.add(tracksGeoJSON)
  } else {
    this.map.on('load', () => {
      this.tracksLayer.add(tracksGeoJSON)
    })
  }
} else {
  this.tracksLayer.update(tracksGeoJSON)
}

// Add helper methods:

areasToGeoJSON(areas) {
  return {
    type: 'FeatureCollection',
    features: areas.map(area => ({
      type: 'Feature',
      geometry: area.geometry,
      properties: {
        id: area.id,
        name: area.name,
        color: area.color || '#3b82f6'
      }
    }))
  }
}

tracksToGeoJSON(tracks) {
  return {
    type: 'FeatureCollection',
    features: tracks.map(track => ({
      type: 'Feature',
      geometry: {
        type: 'LineString',
        coordinates: track.coordinates
      },
      properties: {
        id: track.id,
        name: track.name,
        color: track.color || '#8b5cf6'
      }
    }))
  }
}
```

---

## 5.7 Update API Client

**File**: `app/javascript/maps_v2/services/api_client.js` (add methods)

```javascript
async fetchAreas() {
  const response = await fetch(`${this.baseURL}/areas`, {
    headers: this.getHeaders()
  })

  if (!response.ok) {
    throw new Error(`Failed to fetch areas: ${response.statusText}`)
  }

  return response.json()
}

async fetchTracks() {
  const response = await fetch(`${this.baseURL}/tracks`, {
    headers: this.getHeaders()
  })

  if (!response.ok) {
    throw new Error(`Failed to fetch tracks: ${response.statusText}`)
  }

  return response.json()
}

async createArea(area) {
  const response = await fetch(`${this.baseURL}/areas`, {
    method: 'POST',
    headers: this.getHeaders(),
    body: JSON.stringify({ area })
  })

  if (!response.ok) {
    throw new Error(`Failed to create area: ${response.statusText}`)
  }

  return response.json()
}
```

---

## 🧪 E2E Tests

**File**: `e2e/v2/phase-5-areas.spec.ts`

```typescript
import { test, expect } from '@playwright/test'
import { login, waitForMap } from './helpers/setup'

test.describe('Phase 5: Areas + Drawing Tools', () => {
  test.beforeEach(async ({ page }) => {
    await login(page)
    await page.goto('/maps_v2')
    await waitForMap(page)
  })

  test('areas layer exists', async ({ page }) => {
    const hasAreas = await page.evaluate(() => {
      const map = window.mapInstance
      return map?.getLayer('areas-fill') !== undefined
    })

    expect(hasAreas).toBe(true)
  })

  test('tracks layer exists', async ({ page }) => {
    const hasTracks = await page.evaluate(() => {
      const map = window.mapInstance
      return map?.getLayer('tracks') !== undefined
    })

    expect(hasTracks).toBe(true)
  })

  test('area selection tool works', async ({ page }) => {
    // This would require implementing the UI for area selection
    // Test placeholder
  })

  test('regression - all previous layers work', async ({ page }) => {
    const layers = ['points', 'routes', 'heatmap', 'visits', 'photos']

    for (const layer of layers) {
      const exists = await page.evaluate((l) => {
        const map = window.mapInstance
        return map?.getSource(`${l}-source`) !== undefined
      }, layer)

      expect(exists).toBe(true)
    }
  })
})
```

---

## ✅ Phase 5 Completion Checklist

### Implementation
- [ ] Created areas_layer.js
- [ ] Created tracks_layer.js
- [ ] Created area_selector_controller.js
- [ ] Created area_drawer_controller.js
- [ ] Created geometry.js
- [ ] Updated map_controller.js
- [ ] Updated api_client.js

### Functionality
- [ ] Areas render on map
- [ ] Tracks render on map
- [ ] Rectangle selection works
- [ ] Circle drawing works
- [ ] Areas can be created
- [ ] Areas can be edited
- [ ] Areas can be deleted

### Testing
- [ ] All Phase 5 E2E tests pass
- [ ] Phase 1-4 tests still pass (regression)

---

## 🚀 Deployment

```bash
git checkout -b maps-v2-phase-5
git add app/javascript/maps_v2/ e2e/v2/
git commit -m "feat: Maps V2 Phase 5 - Areas and drawing tools"
git push origin maps-v2-phase-5
```

---

## 🎉 What's Next?

**Phase 6**: Add fog of war, scratch map, and advanced features (keyboard shortcuts, etc.).
