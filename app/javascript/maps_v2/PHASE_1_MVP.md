# Phase 1: MVP - Basic Map with Points

**Timeline**: Week 1
**Goal**: Deploy a minimal viable map showing location points
**Status**: Ready for implementation

## 🎯 Phase Objectives

Create a **working, deployable map application** with:
- ✅ MapLibre GL JS map rendering
- ✅ Points layer with clustering
- ✅ Basic point popups
- ✅ Simple date range selector
- ✅ Loading states
- ✅ API integration for points
- ✅ E2E tests

**Deploy Decision**: Users can view their location history on a map.

---

## 📋 Features Checklist

- [ ] MapLibre map initialization
- [ ] Points layer with automatic clustering
- [ ] Click point to see popup with details
- [ ] Month selector (simple dropdown)
- [ ] Loading indicator while fetching data
- [ ] API client for `/api/v1/points` endpoint
- [ ] Basic error handling
- [ ] E2E tests passing

---

## 🏗️ Files to Create

```
app/javascript/maps_v2/
├── controllers/
│   └── map_controller.js              # Main Stimulus controller
├── services/
│   └── api_client.js                  # API wrapper
├── layers/
│   ├── base_layer.js                  # Base class for layers
│   └── points_layer.js                # Points with clustering
├── utils/
│   └── geojson_transformers.js        # API → GeoJSON
└── components/
    └── popup_factory.js               # Point popups

app/views/maps_v2/
└── index.html.erb                     # Main view

e2e/v2/
├── phase-1-mvp.spec.ts               # E2E tests
└── helpers/
    └── setup.ts                       # Test setup
```

---

## 1.1 Base Layer Class

All layers extend this base class.

**File**: `app/javascript/maps_v2/layers/base_layer.js`

```javascript
/**
 * Base class for all map layers
 * Provides common functionality for layer management
 */
export class BaseLayer {
  constructor(map, options = {}) {
    this.map = map
    this.id = options.id || this.constructor.name.toLowerCase()
    this.sourceId = `${this.id}-source`
    this.visible = options.visible !== false
    this.data = null
  }

  /**
   * Add layer to map with data
   * @param {Object} data - GeoJSON or layer-specific data
   */
  add(data) {
    this.data = data

    // Add source
    if (!this.map.getSource(this.sourceId)) {
      this.map.addSource(this.sourceId, this.getSourceConfig())
    }

    // Add layers
    const layers = this.getLayerConfigs()
    layers.forEach(layerConfig => {
      if (!this.map.getLayer(layerConfig.id)) {
        this.map.addLayer(layerConfig)
      }
    })

    this.setVisibility(this.visible)
  }

  /**
   * Update layer data
   * @param {Object} data - New data
   */
  update(data) {
    this.data = data
    const source = this.map.getSource(this.sourceId)
    if (source && source.setData) {
      source.setData(data)
    }
  }

  /**
   * Remove layer from map
   */
  remove() {
    this.getLayerIds().forEach(layerId => {
      if (this.map.getLayer(layerId)) {
        this.map.removeLayer(layerId)
      }
    })

    if (this.map.getSource(this.sourceId)) {
      this.map.removeSource(this.sourceId)
    }

    this.data = null
  }

  /**
   * Toggle layer visibility
   * @param {boolean} visible - Show/hide layer
   */
  toggle(visible = !this.visible) {
    this.visible = visible
    this.setVisibility(visible)
  }

  /**
   * Set visibility for all layer IDs
   * @param {boolean} visible
   */
  setVisibility(visible) {
    const visibility = visible ? 'visible' : 'none'
    this.getLayerIds().forEach(layerId => {
      if (this.map.getLayer(layerId)) {
        this.map.setLayoutProperty(layerId, 'visibility', visibility)
      }
    })
  }

  /**
   * Get source configuration (override in subclass)
   * @returns {Object} MapLibre source config
   */
  getSourceConfig() {
    throw new Error('Must implement getSourceConfig()')
  }

  /**
   * Get layer configurations (override in subclass)
   * @returns {Array<Object>} Array of MapLibre layer configs
   */
  getLayerConfigs() {
    throw new Error('Must implement getLayerConfigs()')
  }

  /**
   * Get all layer IDs for this layer
   * @returns {Array<string>}
   */
  getLayerIds() {
    return this.getLayerConfigs().map(config => config.id)
  }
}
```

---

## 1.2 Points Layer

Points with clustering support.

**File**: `app/javascript/maps_v2/layers/points_layer.js`

```javascript
import { BaseLayer } from './base_layer'

/**
 * Points layer with automatic clustering
 */
export class PointsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'points', ...options })
    this.clusterRadius = options.clusterRadius || 50
    this.clusterMaxZoom = options.clusterMaxZoom || 14
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || {
        type: 'FeatureCollection',
        features: []
      },
      cluster: true,
      clusterMaxZoom: this.clusterMaxZoom,
      clusterRadius: this.clusterRadius
    }
  }

  getLayerConfigs() {
    return [
      // Cluster circles
      {
        id: `${this.id}-clusters`,
        type: 'circle',
        source: this.sourceId,
        filter: ['has', 'point_count'],
        paint: {
          'circle-color': [
            'step',
            ['get', 'point_count'],
            '#51bbd6', 10,
            '#f1f075', 50,
            '#f28cb1', 100,
            '#ff6b6b'
          ],
          'circle-radius': [
            'step',
            ['get', 'point_count'],
            20, 10,
            30, 50,
            40, 100,
            50
          ]
        }
      },

      // Cluster count labels
      {
        id: `${this.id}-count`,
        type: 'symbol',
        source: this.sourceId,
        filter: ['has', 'point_count'],
        layout: {
          'text-field': '{point_count_abbreviated}',
          'text-font': ['DIN Offc Pro Medium', 'Arial Unicode MS Bold'],
          'text-size': 12
        },
        paint: {
          'text-color': '#ffffff'
        }
      },

      // Individual points
      {
        id: this.id,
        type: 'circle',
        source: this.sourceId,
        filter: ['!', ['has', 'point_count']],
        paint: {
          'circle-color': '#3b82f6',
          'circle-radius': 6,
          'circle-stroke-width': 2,
          'circle-stroke-color': '#ffffff'
        }
      }
    ]
  }
}
```

---

## 1.3 GeoJSON Transformers

Convert API responses to GeoJSON.

**File**: `app/javascript/maps_v2/utils/geojson_transformers.js`

```javascript
/**
 * Transform points array to GeoJSON FeatureCollection
 * @param {Array} points - Array of point objects from API
 * @returns {Object} GeoJSON FeatureCollection
 */
export function pointsToGeoJSON(points) {
  return {
    type: 'FeatureCollection',
    features: points.map(point => ({
      type: 'Feature',
      geometry: {
        type: 'Point',
        coordinates: [point.longitude, point.latitude]
      },
      properties: {
        id: point.id,
        timestamp: point.timestamp,
        altitude: point.altitude,
        battery: point.battery,
        accuracy: point.accuracy,
        velocity: point.velocity
      }
    }))
  }
}

/**
 * Format timestamp for display
 * @param {number} timestamp - Unix timestamp
 * @returns {string} Formatted date/time
 */
export function formatTimestamp(timestamp) {
  const date = new Date(timestamp * 1000)
  return date.toLocaleString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  })
}
```

---

## 1.4 API Client

Wrapper for API endpoints.

**File**: `app/javascript/maps_v2/services/api_client.js`

```javascript
/**
 * API client for Maps V2
 * Wraps all API endpoints with consistent error handling
 */
export class ApiClient {
  constructor(apiKey) {
    this.apiKey = apiKey
    this.baseURL = '/api/v1'
  }

  /**
   * Fetch points for date range (paginated)
   * @param {Object} options - { start_at, end_at, page, per_page }
   * @returns {Promise<Object>} { points, currentPage, totalPages }
   */
  async fetchPoints({ start_at, end_at, page = 1, per_page = 1000 }) {
    const params = new URLSearchParams({
      start_at,
      end_at,
      page: page.toString(),
      per_page: per_page.toString()
    })

    const response = await fetch(`${this.baseURL}/points?${params}`, {
      headers: this.getHeaders()
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch points: ${response.statusText}`)
    }

    const points = await response.json()

    return {
      points,
      currentPage: parseInt(response.headers.get('X-Current-Page') || '1'),
      totalPages: parseInt(response.headers.get('X-Total-Pages') || '1')
    }
  }

  /**
   * Fetch all points for date range (handles pagination)
   * @param {Object} options - { start_at, end_at, onProgress }
   * @returns {Promise<Array>} All points
   */
  async fetchAllPoints({ start_at, end_at, onProgress = null }) {
    const allPoints = []
    let page = 1
    let totalPages = 1

    do {
      const { points, currentPage, totalPages: total } =
        await this.fetchPoints({ start_at, end_at, page, per_page: 1000 })

      allPoints.push(...points)
      totalPages = total
      page++

      if (onProgress) {
        onProgress({
          loaded: allPoints.length,
          currentPage,
          totalPages,
          progress: currentPage / totalPages
        })
      }
    } while (page <= totalPages)

    return allPoints
  }

  getHeaders() {
    return {
      'Authorization': `Bearer ${this.apiKey}`,
      'Content-Type': 'application/json'
    }
  }
}
```

---

## 1.5 Popup Factory

Create popups for points.

**File**: `app/javascript/maps_v2/components/popup_factory.js`

```javascript
import { formatTimestamp } from '../utils/geojson_transformers'

/**
 * Factory for creating map popups
 */
export class PopupFactory {
  /**
   * Create popup for a point
   * @param {Object} properties - Point properties
   * @returns {string} HTML for popup
   */
  static createPointPopup(properties) {
    const { id, timestamp, altitude, battery, accuracy, velocity } = properties

    return `
      <div class="point-popup">
        <div class="popup-header">
          <strong>Point #${id}</strong>
        </div>
        <div class="popup-body">
          <div class="popup-row">
            <span class="label">Time:</span>
            <span class="value">${formatTimestamp(timestamp)}</span>
          </div>
          ${altitude ? `
            <div class="popup-row">
              <span class="label">Altitude:</span>
              <span class="value">${Math.round(altitude)}m</span>
            </div>
          ` : ''}
          ${battery ? `
            <div class="popup-row">
              <span class="label">Battery:</span>
              <span class="value">${battery}%</span>
            </div>
          ` : ''}
          ${accuracy ? `
            <div class="popup-row">
              <span class="label">Accuracy:</span>
              <span class="value">${Math.round(accuracy)}m</span>
            </div>
          ` : ''}
          ${velocity ? `
            <div class="popup-row">
              <span class="label">Speed:</span>
              <span class="value">${Math.round(velocity * 3.6)} km/h</span>
            </div>
          ` : ''}
        </div>
      </div>
    `
  }
}
```

---

## 1.6 Main Map Controller

Stimulus controller orchestrating everything.

**File**: `app/javascript/maps_v2/controllers/map_controller.js`

```javascript
import { Controller } from '@hotwired/stimulus'
import maplibregl from 'maplibre-gl'
import { ApiClient } from '../services/api_client'
import { PointsLayer } from '../layers/points_layer'
import { pointsToGeoJSON } from '../utils/geojson_transformers'
import { PopupFactory } from '../components/popup_factory'

/**
 * Main map controller for Maps V2
 * Phase 1: MVP with points layer
 */
export default class extends Controller {
  static values = {
    apiKey: String,
    startDate: String,
    endDate: String
  }

  static targets = ['container', 'loading', 'monthSelect']

  connect() {
    this.initializeMap()
    this.initializeAPI()
    this.loadMapData()
  }

  disconnect() {
    this.map?.remove()
  }

  /**
   * Initialize MapLibre map
   */
  initializeMap() {
    this.map = new maplibregl.Map({
      container: this.containerTarget,
      style: 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
      center: [0, 0],
      zoom: 2
    })

    // Add navigation controls
    this.map.addControl(new maplibregl.NavigationControl(), 'top-right')

    // Setup click handler for points
    this.map.on('click', 'points', this.handlePointClick.bind(this))

    // Change cursor on hover
    this.map.on('mouseenter', 'points', () => {
      this.map.getCanvas().style.cursor = 'pointer'
    })
    this.map.on('mouseleave', 'points', () => {
      this.map.getCanvas().style.cursor = ''
    })
  }

  /**
   * Initialize API client
   */
  initializeAPI() {
    this.api = new ApiClient(this.apiKeyValue)
  }

  /**
   * Load points data from API
   */
  async loadMapData() {
    this.showLoading()

    try {
      // Fetch all points for selected month
      const points = await this.api.fetchAllPoints({
        start_at: this.startDateValue,
        end_at: this.endDateValue,
        onProgress: this.updateLoadingProgress.bind(this)
      })

      console.log(`Loaded ${points.length} points`)

      // Transform to GeoJSON
      const geojson = pointsToGeoJSON(points)

      // Create/update points layer
      if (!this.pointsLayer) {
        this.pointsLayer = new PointsLayer(this.map)

        // Wait for map to load before adding layer
        if (this.map.loaded()) {
          this.pointsLayer.add(geojson)
        } else {
          this.map.on('load', () => {
            this.pointsLayer.add(geojson)
          })
        }
      } else {
        this.pointsLayer.update(geojson)
      }

      // Fit map to data bounds
      if (points.length > 0) {
        this.fitMapToBounds(geojson)
      }

    } catch (error) {
      console.error('Failed to load map data:', error)
      alert('Failed to load location data. Please try again.')
    } finally {
      this.hideLoading()
    }
  }

  /**
   * Handle point click
   */
  handlePointClick(e) {
    const feature = e.features[0]
    const coordinates = feature.geometry.coordinates.slice()
    const properties = feature.properties

    // Create popup
    new maplibregl.Popup()
      .setLngLat(coordinates)
      .setHTML(PopupFactory.createPointPopup(properties))
      .addTo(this.map)
  }

  /**
   * Fit map to data bounds
   */
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

  /**
   * Month selector changed
   */
  monthChanged(event) {
    const [year, month] = event.target.value.split('-')

    // Update date values
    this.startDateValue = `${year}-${month}-01T00:00:00Z`
    const lastDay = new Date(year, month, 0).getDate()
    this.endDateValue = `${year}-${month}-${lastDay}T23:59:59Z`

    // Reload data
    this.loadMapData()
  }

  /**
   * Show loading indicator
   */
  showLoading() {
    this.loadingTarget.classList.remove('hidden')
  }

  /**
   * Hide loading indicator
   */
  hideLoading() {
    this.loadingTarget.classList.add('hidden')
  }

  /**
   * Update loading progress
   */
  updateLoadingProgress({ loaded, totalPages, progress }) {
    const percentage = Math.round(progress * 100)
    this.loadingTarget.textContent = `Loading... ${percentage}%`
  }
}
```

---

## 1.7 View Template

**File**: `app/views/maps_v2/index.html.erb`

```erb
<div class="maps-v2-container"
     data-controller="map"
     data-map-api-key-value="<%= current_api_user.api_key %>"
     data-map-start-date-value="<%= @start_date.to_s %>"
     data-map-end-date-value="<%= @end_date.to_s %>">

  <!-- Map container -->
  <div class="map-wrapper">
    <div data-map-target="container" class="map-container"></div>

    <!-- Loading overlay -->
    <div data-map-target="loading" class="loading-overlay hidden">
      <div class="loading-spinner"></div>
      <div class="loading-text">Loading points...</div>
    </div>
  </div>

  <!-- Month selector -->
  <div class="controls-panel">
    <div class="control-group">
      <label for="month-select">Month:</label>
      <select id="month-select"
              data-map-target="monthSelect"
              data-action="change->map#monthChanged"
              class="month-selector">
        <% 12.times do |i| %>
          <% date = Date.today.beginning_of_month - i.months %>
          <option value="<%= date.strftime('%Y-%m') %>"
                  <%= 'selected' if date.year == @start_date.year && date.month == @start_date.month %>>
            <%= date.strftime('%B %Y') %>
          </option>
        <% end %>
      </select>
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

  .controls-panel {
    padding: 16px;
    background: white;
    border-top: 1px solid #e5e7eb;
  }

  .control-group {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .control-group label {
    font-weight: 500;
    color: #374151;
  }

  .month-selector {
    padding: 8px 12px;
    border: 1px solid #d1d5db;
    border-radius: 6px;
    font-size: 14px;
  }

  /* Popup styles */
  .point-popup {
    font-family: system-ui, -apple-system, sans-serif;
  }

  .popup-header {
    margin-bottom: 8px;
    padding-bottom: 8px;
    border-bottom: 1px solid #e5e7eb;
  }

  .popup-body {
    font-size: 13px;
  }

  .popup-row {
    display: flex;
    justify-content: space-between;
    gap: 16px;
    padding: 4px 0;
  }

  .popup-row .label {
    color: #6b7280;
  }

  .popup-row .value {
    font-weight: 500;
    color: #111827;
  }
</style>
```

---

## 1.8 Controller (Rails)

**File**: `app/controllers/maps_v2_controller.rb`

```ruby
class MapsV2Controller < ApplicationController
  before_action :authenticate_user!

  def index
    # Default to current month
    @start_date = Date.today.beginning_of_month
    @end_date = Date.today.end_of_month
  end
end
```

---

## 1.9 Routes

**File**: `config/routes.rb` (add)

```ruby
# Maps V2
get '/maps_v2', to: 'maps_v2#index', as: :maps_v2
```

---

## 🧪 E2E Tests

**File**: `e2e/v2/phase-1-mvp.spec.ts`

```typescript
import { test, expect } from '@playwright/test'

test.describe('Phase 1: MVP - Basic Map with Points', () => {
  test.beforeEach(async ({ page }) => {
    // Login
    await page.goto('/users/sign_in')
    await page.fill('input[name="user[email]"]', 'demo@dawarich.app')
    await page.fill('input[name="user[password]"]', 'password')
    await page.click('button[type="submit"]')
    await page.waitForURL('/')

    // Navigate to Maps V2
    await page.goto('/maps_v2')
  })

  test('map container loads', async ({ page }) => {
    const mapContainer = page.locator('[data-map-target="container"]')
    await expect(mapContainer).toBeVisible()
  })

  test('map initializes with MapLibre', async ({ page }) => {
    // Wait for map to load
    await page.waitForSelector('.maplibregl-canvas')

    const canvas = page.locator('.maplibregl-canvas')
    await expect(canvas).toBeVisible()
  })

  test('month selector is present', async ({ page }) => {
    const monthSelect = page.locator('[data-map-target="monthSelect"]')
    await expect(monthSelect).toBeVisible()

    // Should have 12 options
    const options = await monthSelect.locator('option').count()
    expect(options).toBe(12)
  })

  test('points load and render on map', async ({ page }) => {
    // Wait for loading to complete
    await page.waitForSelector('[data-map-target="loading"].hidden', { timeout: 15000 })

    // Check if points source exists
    const hasPoints = await page.evaluate(() => {
      const map = window.mapInstance || document.querySelector('[data-controller="map"]')?.map
      if (!map) return false

      const source = map.getSource('points-source')
      return source && source._data?.features?.length > 0
    })

    expect(hasPoints).toBe(true)
  })

  test('clicking point shows popup', async ({ page }) => {
    // Wait for map to load
    await page.waitForSelector('[data-map-target="loading"].hidden', { timeout: 15000 })

    // Click on map center (likely to have a point)
    const mapContainer = page.locator('[data-map-target="container"]')
    await mapContainer.click({ position: { x: 400, y: 300 } })

    // Wait for popup (may not always appear if no point clicked)
    try {
      await page.waitForSelector('.maplibregl-popup', { timeout: 2000 })
      const popup = page.locator('.maplibregl-popup')
      await expect(popup).toBeVisible()
    } catch (e) {
      console.log('No point clicked, trying again...')
      await mapContainer.click({ position: { x: 500, y: 300 } })
      await page.waitForSelector('.maplibregl-popup', { timeout: 2000 })
    }
  })

  test('changing month selector reloads data', async ({ page }) => {
    // Wait for initial load
    await page.waitForSelector('[data-map-target="loading"].hidden', { timeout: 15000 })

    // Get initial month
    const initialMonth = await page.locator('[data-map-target="monthSelect"]').inputValue()

    // Change month
    await page.selectOption('[data-map-target="monthSelect"]', { index: 1 })

    // Loading should appear
    await expect(page.locator('[data-map-target="loading"]')).not.toHaveClass(/hidden/)

    // Wait for loading to complete
    await page.waitForSelector('[data-map-target="loading"].hidden', { timeout: 15000 })

    // Month should have changed
    const newMonth = await page.locator('[data-map-target="monthSelect"]').inputValue()
    expect(newMonth).not.toBe(initialMonth)
  })

  test('navigation controls are present', async ({ page }) => {
    const navControls = page.locator('.maplibregl-ctrl-top-right')
    await expect(navControls).toBeVisible()

    // Zoom controls
    const zoomIn = page.locator('.maplibregl-ctrl-zoom-in')
    const zoomOut = page.locator('.maplibregl-ctrl-zoom-out')
    await expect(zoomIn).toBeVisible()
    await expect(zoomOut).toBeVisible()
  })

  test('map fits bounds to data', async ({ page }) => {
    await page.waitForSelector('[data-map-target="loading"].hidden', { timeout: 15000 })

    // Get map zoom level (should be > 2 if fitBounds worked)
    const zoom = await page.evaluate(() => {
      const map = window.mapInstance || document.querySelector('[data-controller="map"]')?.map
      return map?.getZoom()
    })

    expect(zoom).toBeGreaterThan(2)
  })

  test('loading indicator shows during fetch', async ({ page }) => {
    // Reload page to see loading
    await page.reload()

    // Loading should be visible
    const loading = page.locator('[data-map-target="loading"]')
    await expect(loading).not.toHaveClass(/hidden/)

    // Wait for it to hide
    await page.waitForSelector('[data-map-target="loading"].hidden', { timeout: 15000 })
  })
})
```

**File**: `e2e/v2/helpers/setup.ts`

```typescript
import { Page } from '@playwright/test'

/**
 * Login helper for E2E tests
 */
export async function login(page: Page, email = 'demo@dawarich.app', password = 'password') {
  await page.goto('/users/sign_in')
  await page.fill('input[name="user[email]"]', email)
  await page.fill('input[name="user[password]"]', password)
  await page.click('button[type="submit"]')
  await page.waitForURL('/')
}

/**
 * Wait for map to be ready
 */
export async function waitForMap(page: Page) {
  await page.waitForSelector('.maplibregl-canvas')
  await page.waitForSelector('[data-map-target="loading"].hidden', { timeout: 15000 })
}

/**
 * Expose map instance for testing
 */
export async function exposeMapInstance(page: Page) {
  await page.evaluate(() => {
    const controller = document.querySelector('[data-controller="map"]')
    if (controller && controller.map) {
      window.mapInstance = controller.map
    }
  })
}
```

---

## ✅ Phase 1 Completion Checklist

### Implementation
- [ ] Created all JavaScript files
- [ ] Created view template
- [ ] Added controller and routes
- [ ] Installed MapLibre GL JS (`npm install maplibre-gl`)
- [ ] Map renders successfully
- [ ] Points load and display
- [ ] Clustering works
- [ ] Popups show on click
- [ ] Month selector changes data

### Testing
- [ ] All E2E tests pass (`npx playwright test e2e/v2/phase-1-mvp.spec.ts`)
- [ ] Manual testing complete
- [ ] Tested on mobile viewport
- [ ] Tested on desktop viewport
- [ ] No console errors

### Performance
- [ ] Map loads in < 3 seconds
- [ ] Points render smoothly
- [ ] No memory leaks (check DevTools)

### Documentation
- [ ] Code comments added
- [ ] README updated with Phase 1 status

---

## 🚀 Deployment

### Staging Deployment
```bash
git checkout -b maps-v2-phase-1
git add app/javascript/maps_v2/ app/views/maps_v2/ app/controllers/maps_v2_controller.rb
git commit -m "feat: Maps V2 Phase 1 - MVP with points layer"
git push origin maps-v2-phase-1

# Deploy to staging
# Test at: https://staging.example.com/maps_v2
```

### Production Deployment
After staging approval:
```bash
git checkout main
git merge maps-v2-phase-1
git push origin main
```

---

## 🔄 Rollback Plan

If issues arise:
```bash
# Revert deployment
git revert HEAD

# Or disable route
# In config/routes.rb, comment out:
# get '/maps_v2', to: 'maps_v2#index'
```

---

## 📊 Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| Map loads | < 3s | E2E test timing |
| Points render | All visible | E2E test assertion |
| Clustering | Works at zoom < 14 | Manual testing |
| Popup | Shows on click | E2E test |
| Month selector | Changes data | E2E test |
| No errors | 0 console errors | Browser DevTools |

---

## 🎉 What's Next?

After Phase 1 is deployed and tested:
- **Phase 2**: Add routes layer and enhanced date navigation
- Get user feedback on Phase 1
- Monitor performance metrics
- Plan Phase 2 timeline

**Phase 1 Complete!** You now have a working location history map. 🗺️
