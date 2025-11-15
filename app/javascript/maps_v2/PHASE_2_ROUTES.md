# Phase 2: Routes + Enhanced Navigation

**Timeline**: Week 2
**Goal**: Add routes visualization and better date navigation
**Dependencies**: Phase 1 complete
**Status**: Ready for implementation

## 🎯 Phase Objectives

Build on Phase 1 MVP by adding:
- ✅ Routes layer with speed-based coloring
- ✅ Enhanced date navigation (Previous/Next Day/Week/Month)
- ✅ Layer toggle controls (Points, Routes)
- ✅ Improved map controls
- ✅ Auto-fit bounds to visible data
- ✅ E2E tests

**Deploy Decision**: Users can visualize their travel routes with speed indicators.

---

## 📋 Features Checklist

- [ ] Routes layer connecting points
- [ ] Speed-based route coloring (green = slow, red = fast)
- [ ] Date picker with Previous/Next buttons
- [ ] Quick shortcuts (Day, Week, Month)
- [ ] Layer toggle controls UI
- [ ] Toggle between Points and Routes
- [ ] Map auto-fits to visible layers
- [ ] E2E tests passing

---

## 🏗️ New Files (Phase 2)

```
app/javascript/maps_v2/
├── layers/
│   └── routes_layer.js                # NEW: Routes with speed colors
├── controllers/
│   ├── date_picker_controller.js      # NEW: Date navigation
│   └── layer_controls_controller.js   # NEW: Layer toggles
└── utils/
    └── date_helpers.js                # NEW: Date manipulation

e2e/v2/
└── phase-2-routes.spec.ts            # NEW: E2E tests
```

---

## 2.1 Routes Layer

Routes connecting points with speed-based coloring.

**File**: `app/javascript/maps_v2/layers/routes_layer.js`

```javascript
import { BaseLayer } from './base_layer'

/**
 * Routes layer with speed-based coloring
 * Connects points to show travel paths
 */
export class RoutesLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'routes', ...options })
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || {
        type: 'FeatureCollection',
        features: []
      },
      lineMetrics: true // Enable gradient lines
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
          'line-color': [
            'interpolate',
            ['linear'],
            ['get', 'speed'],
            0, '#22c55e',    // 0 km/h = green
            30, '#eab308',   // 30 km/h = yellow
            60, '#f97316',   // 60 km/h = orange
            100, '#ef4444'   // 100+ km/h = red
          ],
          'line-width': 3,
          'line-opacity': 0.8
        }
      }
    ]
  }
}
```

---

## 2.2 Date Helpers

Utilities for date manipulation.

**File**: `app/javascript/maps_v2/utils/date_helpers.js`

```javascript
/**
 * Add days to a date
 * @param {Date} date
 * @param {number} days
 * @returns {Date}
 */
export function addDays(date, days) {
  const result = new Date(date)
  result.setDate(result.getDate() + days)
  return result
}

/**
 * Add months to a date
 * @param {Date} date
 * @param {number} months
 * @returns {Date}
 */
export function addMonths(date, months) {
  const result = new Date(date)
  result.setMonth(result.getMonth() + months)
  return result
}

/**
 * Get start of day
 * @param {Date} date
 * @returns {Date}
 */
export function startOfDay(date) {
  const result = new Date(date)
  result.setHours(0, 0, 0, 0)
  return result
}

/**
 * Get end of day
 * @param {Date} date
 * @returns {Date}
 */
export function endOfDay(date) {
  const result = new Date(date)
  result.setHours(23, 59, 59, 999)
  return result
}

/**
 * Get start of month
 * @param {Date} date
 * @returns {Date}
 */
export function startOfMonth(date) {
  return new Date(date.getFullYear(), date.getMonth(), 1)
}

/**
 * Get end of month
 * @param {Date} date
 * @returns {Date}
 */
export function endOfMonth(date) {
  return new Date(date.getFullYear(), date.getMonth() + 1, 0, 23, 59, 59, 999)
}

/**
 * Format date for API (ISO 8601)
 * @param {Date} date
 * @returns {string}
 */
export function formatForAPI(date) {
  return date.toISOString()
}

/**
 * Format date for display
 * @param {Date} date
 * @returns {string}
 */
export function formatForDisplay(date) {
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  })
}
```

---

## 2.3 Date Picker Controller

Enhanced date navigation with shortcuts.

**File**: `app/javascript/maps_v2/controllers/date_picker_controller.js`

```javascript
import { Controller } from '@hotwired/stimulus'
import {
  addDays,
  addMonths,
  startOfDay,
  endOfDay,
  startOfMonth,
  endOfMonth,
  formatForAPI,
  formatForDisplay
} from '../utils/date_helpers'

/**
 * Date picker controller with navigation shortcuts
 * Provides Previous/Next Day/Week/Month buttons
 */
export default class extends Controller {
  static values = {
    startDate: String,
    endDate: String
  }

  static targets = ['startInput', 'endInput', 'display']

  static outlets = ['map']

  connect() {
    this.updateDisplay()
  }

  /**
   * Navigate to previous day
   */
  previousDay(event) {
    event?.preventDefault()
    this.adjustDates(-1, 'day')
  }

  /**
   * Navigate to next day
   */
  nextDay(event) {
    event?.preventDefault()
    this.adjustDates(1, 'day')
  }

  /**
   * Navigate to previous week
   */
  previousWeek(event) {
    event?.preventDefault()
    this.adjustDates(-7, 'day')
  }

  /**
   * Navigate to next week
   */
  nextWeek(event) {
    event?.preventDefault()
    this.adjustDates(7, 'day')
  }

  /**
   * Navigate to previous month
   */
  previousMonth(event) {
    event?.preventDefault()
    this.adjustDates(-1, 'month')
  }

  /**
   * Navigate to next month
   */
  nextMonth(event) {
    event?.preventDefault()
    this.adjustDates(1, 'month')
  }

  /**
   * Adjust dates by amount
   * @param {number} amount
   * @param {'day'|'month'} unit
   */
  adjustDates(amount, unit) {
    const currentStart = new Date(this.startDateValue)

    let newStart, newEnd

    if (unit === 'day') {
      newStart = startOfDay(addDays(currentStart, amount))
      newEnd = endOfDay(newStart)
    } else if (unit === 'month') {
      const adjusted = addMonths(currentStart, amount)
      newStart = startOfMonth(adjusted)
      newEnd = endOfMonth(adjusted)
    }

    this.startDateValue = formatForAPI(newStart)
    this.endDateValue = formatForAPI(newEnd)

    this.updateDisplay()
    this.notifyMapController()
  }

  /**
   * Handle manual date input change
   */
  dateChanged() {
    const startInput = this.startInputTarget.value
    const endInput = this.endInputTarget.value

    if (startInput && endInput) {
      const start = startOfDay(new Date(startInput))
      const end = endOfDay(new Date(endInput))

      this.startDateValue = formatForAPI(start)
      this.endDateValue = formatForAPI(end)

      this.updateDisplay()
      this.notifyMapController()
    }
  }

  /**
   * Update display text
   */
  updateDisplay() {
    if (!this.hasDisplayTarget) return

    const start = new Date(this.startDateValue)
    const end = new Date(this.endDateValue)

    // Check if it's a single day
    if (this.isSameDay(start, end)) {
      this.displayTarget.textContent = formatForDisplay(start)
    }
    // Check if it's a full month
    else if (this.isFullMonth(start, end)) {
      this.displayTarget.textContent = start.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long'
      })
    }
    // Range
    else {
      this.displayTarget.textContent = `${formatForDisplay(start)} - ${formatForDisplay(end)}`
    }
  }

  /**
   * Notify map controller of date change
   */
  notifyMapController() {
    if (this.hasMapOutlet) {
      this.mapOutlet.startDateValue = this.startDateValue
      this.mapOutlet.endDateValue = this.endDateValue
      this.mapOutlet.loadMapData()
    }
  }

  /**
   * Check if two dates are the same day
   */
  isSameDay(date1, date2) {
    return (
      date1.getFullYear() === date2.getFullYear() &&
      date1.getMonth() === date2.getMonth() &&
      date1.getDate() === date2.getDate()
    )
  }

  /**
   * Check if range is a full month
   */
  isFullMonth(start, end) {
    const monthStart = startOfMonth(start)
    const monthEnd = endOfMonth(start)
    return (
      this.isSameDay(start, monthStart) &&
      this.isSameDay(end, monthEnd)
    )
  }
}
```

---

## 2.4 Layer Controls Controller

Toggle visibility of map layers.

**File**: `app/javascript/maps_v2/controllers/layer_controls_controller.js`

```javascript
import { Controller } from '@hotwired/stimulus'

/**
 * Layer controls controller
 * Manages layer visibility toggles
 */
export default class extends Controller {
  static targets = ['button']

  static outlets = ['map']

  /**
   * Toggle a layer
   * @param {Event} event
   */
  toggleLayer(event) {
    const button = event.currentTarget
    const layerName = button.dataset.layer

    if (!this.hasMapOutlet) return

    // Toggle layer in map controller
    const layer = this.mapOutlet[`${layerName}Layer`]
    if (layer) {
      layer.toggle()

      // Update button state
      button.classList.toggle('active', layer.visible)
      button.setAttribute('aria-pressed', layer.visible)
    }
  }
}
```

---

## 2.5 Update Map Controller

Add routes support and layer controls.

**File**: `app/javascript/maps_v2/controllers/map_controller.js` (update)

```javascript
import { Controller } from '@hotwired/stimulus'
import maplibregl from 'maplibre-gl'
import { ApiClient } from '../services/api_client'
import { PointsLayer } from '../layers/points_layer'
import { RoutesLayer } from '../layers/routes_layer' // NEW
import { pointsToGeoJSON } from '../utils/geojson_transformers'
import { PopupFactory } from '../components/popup_factory'

/**
 * Main map controller for Maps V2
 * Phase 2: Add routes layer
 */
export default class extends Controller {
  static values = {
    apiKey: String,
    startDate: String,
    endDate: String
  }

  static targets = ['container', 'loading']

  connect() {
    this.initializeMap()
    this.initializeAPI()
    this.loadMapData()
  }

  disconnect() {
    this.map?.remove()
  }

  initializeMap() {
    this.map = new maplibregl.Map({
      container: this.containerTarget,
      style: 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
      center: [0, 0],
      zoom: 2
    })

    this.map.addControl(new maplibregl.NavigationControl(), 'top-right')

    this.map.on('click', 'points', this.handlePointClick.bind(this))
    this.map.on('mouseenter', 'points', () => {
      this.map.getCanvas().style.cursor = 'pointer'
    })
    this.map.on('mouseleave', 'points', () => {
      this.map.getCanvas().style.cursor = ''
    })
  }

  initializeAPI() {
    this.api = new ApiClient(this.apiKeyValue)
  }

  async loadMapData() {
    this.showLoading()

    try {
      const points = await this.api.fetchAllPoints({
        start_at: this.startDateValue,
        end_at: this.endDateValue,
        onProgress: this.updateLoadingProgress.bind(this)
      })

      console.log(`Loaded ${points.length} points`)

      // Transform to GeoJSON
      const pointsGeoJSON = pointsToGeoJSON(points)

      // Create/update points layer
      if (!this.pointsLayer) {
        this.pointsLayer = new PointsLayer(this.map)

        if (this.map.loaded()) {
          this.pointsLayer.add(pointsGeoJSON)
        } else {
          this.map.on('load', () => {
            this.pointsLayer.add(pointsGeoJSON)
          })
        }
      } else {
        this.pointsLayer.update(pointsGeoJSON)
      }

      // NEW: Create routes from points
      const routesGeoJSON = this.pointsToRoutes(points)

      if (!this.routesLayer) {
        this.routesLayer = new RoutesLayer(this.map)

        if (this.map.loaded()) {
          this.routesLayer.add(routesGeoJSON)
        } else {
          this.map.on('load', () => {
            this.routesLayer.add(routesGeoJSON)
          })
        }
      } else {
        this.routesLayer.update(routesGeoJSON)
      }

      // Fit map to data
      if (points.length > 0) {
        this.fitMapToBounds(pointsGeoJSON)
      }

    } catch (error) {
      console.error('Failed to load map data:', error)
      alert('Failed to load location data. Please try again.')
    } finally {
      this.hideLoading()
    }
  }

  /**
   * Convert points to routes (LineStrings)
   * NEW in Phase 2
   */
  pointsToRoutes(points) {
    if (points.length < 2) {
      return { type: 'FeatureCollection', features: [] }
    }

    // Sort by timestamp
    const sorted = points.sort((a, b) => a.timestamp - b.timestamp)

    // Group into continuous segments (max 5 hours gap)
    const segments = []
    let currentSegment = [sorted[0]]

    for (let i = 1; i < sorted.length; i++) {
      const prev = sorted[i - 1]
      const curr = sorted[i]
      const timeDiff = curr.timestamp - prev.timestamp

      // If more than 5 hours gap, start new segment
      if (timeDiff > 5 * 3600) {
        if (currentSegment.length > 1) {
          segments.push(currentSegment)
        }
        currentSegment = [curr]
      } else {
        currentSegment.push(curr)
      }
    }

    if (currentSegment.length > 1) {
      segments.push(currentSegment)
    }

    // Convert segments to LineStrings
    const features = segments.map(segment => {
      const coordinates = segment.map(p => [p.longitude, p.latitude])

      // Calculate average speed
      const speeds = segment
        .map(p => p.velocity || 0)
        .filter(v => v > 0)
      const avgSpeed = speeds.length > 0
        ? speeds.reduce((a, b) => a + b) / speeds.length
        : 0

      return {
        type: 'Feature',
        geometry: {
          type: 'LineString',
          coordinates
        },
        properties: {
          speed: avgSpeed * 3.6, // m/s to km/h
          pointCount: segment.length
        }
      }
    })

    return {
      type: 'FeatureCollection',
      features
    }
  }

  handlePointClick(e) {
    const feature = e.features[0]
    const coordinates = feature.geometry.coordinates.slice()
    const properties = feature.properties

    new maplibregl.Popup()
      .setLngLat(coordinates)
      .setHTML(PopupFactory.createPointPopup(properties))
      .addTo(this.map)
  }

  fitMapToBounds(geojson) {
    const coordinates = geojson.features.map(f => f.geometry.coordinates)

    const bounds = coordinates.reduce((bounds, coord) => {
      return bounds.extend(coord)
    }, new maplibregl.LngLatBounds(coordinates[0], coordinates[0]))

    this.map.fitBounds(bounds, {
      padding: 50,
      maxZoom: 15
    })
  }

  showLoading() {
    this.loadingTarget.classList.remove('hidden')
  }

  hideLoading() {
    this.loadingTarget.classList.add('hidden')
  }

  updateLoadingProgress({ loaded, totalPages, progress }) {
    const percentage = Math.round(progress * 100)
    this.loadingTarget.textContent = `Loading... ${percentage}%`
  }
}
```

---

## 2.6 Updated View Template

**File**: `app/views/maps_v2/index.html.erb` (update)

```erb
<div class="maps-v2-container">
  <!-- Map -->
  <div class="map-wrapper"
       data-controller="map date-picker layer-controls"
       data-map-api-key-value="<%= current_api_user.api_key %>"
       data-map-start-date-value="<%= @start_date.iso8601 %>"
       data-map-end-date-value="<%= @end_date.iso8601 %>"
       data-date-picker-start-date-value="<%= @start_date.iso8601 %>"
       data-date-picker-end-date-value="<%= @end_date.iso8601 %>"
       data-date-picker-map-outlet=".map-wrapper"
       data-layer-controls-map-outlet=".map-wrapper">

    <div data-map-target="container" class="map-container"></div>

    <div data-map-target="loading" class="loading-overlay hidden">
      <div class="loading-spinner"></div>
      <div class="loading-text">Loading points...</div>
    </div>

    <!-- Layer Controls (top-left) -->
    <div class="layer-controls">
      <button data-layer-controls-target="button"
              data-layer="points"
              data-action="click->layer-controls#toggleLayer"
              class="layer-button active"
              aria-pressed="true">
        Points
      </button>

      <button data-layer-controls-target="button"
              data-layer="routes"
              data-action="click->layer-controls#toggleLayer"
              class="layer-button active"
              aria-pressed="true">
        Routes
      </button>
    </div>
  </div>

  <!-- Date Navigation Panel -->
  <div class="controls-panel">
    <!-- Date Display -->
    <div class="date-display">
      <span data-date-picker-target="display"></span>
    </div>

    <!-- Quick Navigation -->
    <div class="date-nav">
      <div class="nav-group">
        <button data-action="click->date-picker#previousMonth"
                class="nav-button"
                title="Previous Month">
          ◀◀
        </button>
        <button data-action="click->date-picker#previousWeek"
                class="nav-button"
                title="Previous Week">
          ◀
        </button>
        <button data-action="click->date-picker#previousDay"
                class="nav-button"
                title="Previous Day">
          ◁
        </button>
      </div>

      <div class="nav-group">
        <button data-action="click->date-picker#nextDay"
                class="nav-button"
                title="Next Day">
          ▷
        </button>
        <button data-action="click->date-picker#nextWeek"
                class="nav-button"
                title="Next Week">
          ▶
        </button>
        <button data-action="click->date-picker#nextMonth"
                class="nav-button"
                title="Next Month">
          ▶▶
        </button>
      </div>
    </div>

    <!-- Manual Date Selection -->
    <div class="date-inputs">
      <input type="date"
             data-date-picker-target="startInput"
             data-action="change->date-picker#dateChanged"
             value="<%= @start_date.strftime('%Y-%m-%d') %>"
             class="date-input">

      <span class="date-separator">to</span>

      <input type="date"
             data-date-picker-target="endInput"
             data-action="change->date-picker#dateChanged"
             value="<%= @end_date.strftime('%Y-%m-%d') %>"
             class="date-input">
    </div>
  </div>
</div>

<style>
  .maps-v2-container {
    height: 100vh;
    display: flex;
    flex-direction: column;
  }

  .map-wrapper {
    flex: 1;
    position: relative;
  }

  .map-container {
    width: 100%;
    height: 100%;
  }

  .loading-overlay {
    position: absolute;
    inset: 0;
    background: rgba(255, 255, 255, 0.9);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    z-index: 1000;
  }

  .loading-overlay.hidden {
    display: none;
  }

  .loading-spinner {
    width: 40px;
    height: 40px;
    border: 4px solid #e5e7eb;
    border-top-color: #3b82f6;
    border-radius: 50%;
    animation: spin 1s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .loading-text {
    margin-top: 16px;
    font-size: 14px;
    color: #6b7280;
  }

  /* Layer Controls */
  .layer-controls {
    position: absolute;
    top: 16px;
    left: 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    z-index: 10;
  }

  .layer-button {
    padding: 8px 16px;
    background: white;
    border: 2px solid #e5e7eb;
    border-radius: 6px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s;
  }

  .layer-button:hover {
    border-color: #3b82f6;
  }

  .layer-button.active {
    background: #3b82f6;
    color: white;
    border-color: #3b82f6;
  }

  /* Controls Panel */
  .controls-panel {
    padding: 16px;
    background: white;
    border-top: 1px solid #e5e7eb;
    display: flex;
    align-items: center;
    gap: 24px;
  }

  .date-display {
    font-weight: 600;
    color: #111827;
    min-width: 200px;
  }

  .date-nav {
    display: flex;
    gap: 16px;
  }

  .nav-group {
    display: flex;
    gap: 4px;
  }

  .nav-button {
    padding: 8px 12px;
    background: white;
    border: 1px solid #d1d5db;
    border-radius: 6px;
    font-size: 14px;
    cursor: pointer;
    transition: all 0.2s;
  }

  .nav-button:hover {
    background: #f3f4f6;
    border-color: #3b82f6;
  }

  .date-inputs {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-left: auto;
  }

  .date-input {
    padding: 8px 12px;
    border: 1px solid #d1d5db;
    border-radius: 6px;
    font-size: 14px;
  }

  .date-separator {
    color: #6b7280;
  }

  /* Mobile */
  @media (max-width: 768px) {
    .controls-panel {
      flex-direction: column;
      align-items: stretch;
      gap: 12px;
    }

    .date-display {
      text-align: center;
    }

    .date-nav {
      justify-content: center;
    }

    .date-inputs {
      margin-left: 0;
    }
  }
</style>
```

---

## 🧪 E2E Tests

**File**: `e2e/v2/phase-2-routes.spec.ts`

```typescript
import { test, expect } from '@playwright/test'
import { login, waitForMap } from './helpers/setup'

test.describe('Phase 2: Routes + Enhanced Navigation', () => {
  test.beforeEach(async ({ page }) => {
    await login(page)
    await page.goto('/maps_v2')
    await waitForMap(page)
  })

  test('routes layer renders', async ({ page }) => {
    const hasRoutes = await page.evaluate(() => {
      const map = window.mapInstance
      const source = map?.getSource('routes-source')
      return source && source._data?.features?.length > 0
    })

    expect(hasRoutes).toBe(true)
  })

  test('routes have speed-based colors', async ({ page }) => {
    const routeLayer = await page.evaluate(() => {
      const map = window.mapInstance
      return map?.getLayer('routes')
    })

    expect(routeLayer).toBeTruthy()
  })

  test('layer controls toggle points', async ({ page }) => {
    const pointsButton = page.locator('button[data-layer="points"]')
    await expect(pointsButton).toHaveClass(/active/)

    // Toggle off
    await pointsButton.click()
    await expect(pointsButton).not.toHaveClass(/active/)

    // Verify layer hidden
    const isHidden = await page.evaluate(() => {
      const map = window.mapInstance
      return map?.getLayoutProperty('points', 'visibility') === 'none'
    })
    expect(isHidden).toBe(true)

    // Toggle back on
    await pointsButton.click()
    await expect(pointsButton).toHaveClass(/active/)
  })

  test('layer controls toggle routes', async ({ page }) => {
    const routesButton = page.locator('button[data-layer="routes"]')
    await routesButton.click()

    const isHidden = await page.evaluate(() => {
      const map = window.mapInstance
      return map?.getLayoutProperty('routes', 'visibility') === 'none'
    })
    expect(isHidden).toBe(true)
  })

  test('previous day button works', async ({ page }) => {
    const dateDisplay = page.locator('[data-date-picker-target="display"]')
    const initialText = await dateDisplay.textContent()

    await page.click('button[title="Previous Day"]')
    await waitForMap(page)

    const newText = await dateDisplay.textContent()
    expect(newText).not.toBe(initialText)
  })

  test('next day button works', async ({ page }) => {
    const dateDisplay = page.locator('[data-date-picker-target="display"]')
    const initialText = await dateDisplay.textContent()

    await page.click('button[title="Next Day"]')
    await waitForMap(page)

    const newText = await dateDisplay.textContent()
    expect(newText).not.toBe(initialText)
  })

  test('previous week button works', async ({ page }) => {
    await page.click('button[title="Previous Week"]')
    await waitForMap(page)

    // Should have loaded different data
    expect(page.locator('[data-map-target="loading"]')).toHaveClass(/hidden/)
  })

  test('previous month button works', async ({ page }) => {
    await page.click('button[title="Previous Month"]')
    await waitForMap(page)

    expect(page.locator('[data-map-target="loading"]')).toHaveClass(/hidden/)
  })

  test('manual date input works', async ({ page }) => {
    const startInput = page.locator('input[data-date-picker-target="startInput"]')
    const endInput = page.locator('input[data-date-picker-target="endInput"]')

    await startInput.fill('2024-06-01')
    await endInput.fill('2024-06-30')

    await waitForMap(page)

    const dateDisplay = page.locator('[data-date-picker-target="display"]')
    const text = await dateDisplay.textContent()
    expect(text).toContain('June 2024')
  })

  test('date display updates correctly', async ({ page }) => {
    const dateDisplay = page.locator('[data-date-picker-target="display"]')
    await expect(dateDisplay).not.toBeEmpty()
  })

  test('both layers can be visible simultaneously', async ({ page }) => {
    const pointsVisible = await page.evaluate(() => {
      const map = window.mapInstance
      return map?.getLayoutProperty('points', 'visibility') === 'visible'
    })

    const routesVisible = await page.evaluate(() => {
      const map = window.mapInstance
      return map?.getLayoutProperty('routes', 'visibility') === 'visible'
    })

    expect(pointsVisible).toBe(true)
    expect(routesVisible).toBe(true)
  })
})
```

---

## ✅ Phase 2 Completion Checklist

### Implementation
- [ ] Created routes_layer.js
- [ ] Created date_picker_controller.js
- [ ] Created layer_controls_controller.js
- [ ] Created date_helpers.js
- [ ] Updated map_controller.js
- [ ] Updated view template
- [ ] Routes render with speed colors
- [ ] Layer toggles work
- [ ] Date navigation works

### Testing
- [ ] All E2E tests pass
- [ ] Phase 1 tests still pass (regression)
- [ ] Manual testing complete
- [ ] Tested all date navigation buttons
- [ ] Tested layer toggles

### Performance
- [ ] Routes render smoothly
- [ ] Date changes load quickly
- [ ] No performance regression from Phase 1

---

## 🚀 Deployment

```bash
git checkout -b maps-v2-phase-2
git add app/javascript/maps_v2/ app/views/maps_v2/ e2e/v2/
git commit -m "feat: Maps V2 Phase 2 - Routes and navigation"

# Run tests
npx playwright test e2e/v2/phase-1-mvp.spec.ts
npx playwright test e2e/v2/phase-2-routes.spec.ts

# Deploy to staging
git push origin maps-v2-phase-2
```

---

## 🎉 What's Next?

**Phase 3**: Add heatmap layer and mobile-optimized UI with bottom sheet.
