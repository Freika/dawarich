# Phase 3: Heatmap + Mobile UI

**Timeline**: Week 3
**Goal**: Add heatmap visualization and mobile-first UI
**Dependencies**: Phase 1 & 2 complete
**Status**: Ready for implementation

## 🎯 Phase Objectives

Build on Phases 1 & 2 by adding:
- ✅ Heatmap layer for density visualization
- ✅ Mobile-first bottom sheet UI
- ✅ Touch gesture support (swipe, pinch)
- ✅ Settings panel with preferences
- ✅ Responsive breakpoints
- ✅ E2E tests

**Deploy Decision**: Users get a mobile-optimized map with density visualization.

---

## 📋 Features Checklist

- [ ] Heatmap layer showing point density
- [ ] Bottom sheet UI (collapsed/half/full states)
- [ ] Swipe gestures for bottom sheet
- [ ] Settings panel (map style, clustering options)
- [ ] Responsive layout (mobile vs desktop)
- [ ] Pinch-to-zoom gesture support
- [ ] Touch-optimized controls
- [ ] E2E tests passing

---

## 🏗️ New Files (Phase 3)

```
app/javascript/maps_v2/
├── layers/
│   └── heatmap_layer.js               # NEW: Density heatmap
├── controllers/
│   ├── bottom_sheet_controller.js     # NEW: Mobile bottom sheet
│   └── settings_panel_controller.js   # NEW: Settings UI
└── utils/
    ├── gestures.js                    # NEW: Touch gestures
    └── responsive.js                  # NEW: Breakpoint utilities

app/views/maps_v2/
└── _bottom_sheet.html.erb             # NEW: Bottom sheet partial
└── _settings_panel.html.erb           # NEW: Settings partial

e2e/v2/
└── phase-3-mobile.spec.ts             # NEW: E2E tests
```

---

## 3.1 Heatmap Layer

Density-based visualization using MapLibre heatmap.

**File**: `app/javascript/maps_v2/layers/heatmap_layer.js`

```javascript
import { BaseLayer } from './base_layer'

/**
 * Heatmap layer showing point density
 * Uses MapLibre's native heatmap for performance
 */
export class HeatmapLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'heatmap', ...options })
    this.radius = options.radius || 20
    this.weight = options.weight || 1
    this.intensity = options.intensity || 1
    this.opacity = options.opacity || 0.6
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
        type: 'heatmap',
        source: this.sourceId,
        paint: {
          // Increase weight as diameter increases
          'heatmap-weight': [
            'interpolate',
            ['linear'],
            ['get', 'weight'],
            0, 0,
            6, 1
          ],

          // Increase intensity as zoom increases
          'heatmap-intensity': [
            'interpolate',
            ['linear'],
            ['zoom'],
            0, this.intensity,
            9, this.intensity * 3
          ],

          // Color ramp from blue to red
          'heatmap-color': [
            'interpolate',
            ['linear'],
            ['heatmap-density'],
            0, 'rgba(33,102,172,0)',
            0.2, 'rgb(103,169,207)',
            0.4, 'rgb(209,229,240)',
            0.6, 'rgb(253,219,199)',
            0.8, 'rgb(239,138,98)',
            1, 'rgb(178,24,43)'
          ],

          // Adjust radius by zoom level
          'heatmap-radius': [
            'interpolate',
            ['linear'],
            ['zoom'],
            0, this.radius,
            9, this.radius * 3
          ],

          // Transition from heatmap to circle layer by zoom level
          'heatmap-opacity': [
            'interpolate',
            ['linear'],
            ['zoom'],
            7, this.opacity,
            9, 0
          ]
        }
      }
    ]
  }

  /**
   * Update intensity
   * @param {number} intensity - 0-2
   */
  setIntensity(intensity) {
    this.intensity = intensity
    this.map.setPaintProperty(this.id, 'heatmap-intensity', [
      'interpolate',
      ['linear'],
      ['zoom'],
      0, intensity,
      9, intensity * 3
    ])
  }

  /**
   * Update radius
   * @param {number} radius - Pixel radius
   */
  setRadius(radius) {
    this.radius = radius
    this.map.setPaintProperty(this.id, 'heatmap-radius', [
      'interpolate',
      ['linear'],
      ['zoom'],
      0, radius,
      9, radius * 3
    ])
  }

  /**
   * Update opacity
   * @param {number} opacity - 0-1
   */
  setOpacity(opacity) {
    this.opacity = opacity
    this.map.setPaintProperty(this.id, 'heatmap-opacity', [
      'interpolate',
      ['linear'],
      ['zoom'],
      7, opacity,
      9, 0
    ])
  }
}
```

---

## 3.2 Touch Gestures Utilities

**File**: `app/javascript/maps_v2/utils/gestures.js`

```javascript
/**
 * Touch gesture utilities
 * Handles swipe, pinch, long-press detection
 */

export class GestureDetector {
  constructor(element, options = {}) {
    this.element = element
    this.threshold = options.threshold || 50
    this.longPressDelay = options.longPressDelay || 500

    this.touchStartX = 0
    this.touchStartY = 0
    this.touchEndX = 0
    this.touchEndY = 0
    this.touchStartTime = 0
    this.longPressTimer = null

    this.onSwipeUp = options.onSwipeUp || null
    this.onSwipeDown = options.onSwipeDown || null
    this.onSwipeLeft = options.onSwipeLeft || null
    this.onSwipeRight = options.onSwipeRight || null
    this.onLongPress = options.onLongPress || null

    this.bind()
  }

  bind() {
    this.element.addEventListener('touchstart', this.handleTouchStart.bind(this), { passive: true })
    this.element.addEventListener('touchend', this.handleTouchEnd.bind(this), { passive: true })
    this.element.addEventListener('touchmove', this.handleTouchMove.bind(this), { passive: true })
  }

  handleTouchStart(e) {
    const touch = e.touches[0]
    this.touchStartX = touch.clientX
    this.touchStartY = touch.clientY
    this.touchStartTime = Date.now()

    // Start long press timer
    if (this.onLongPress) {
      this.longPressTimer = setTimeout(() => {
        this.onLongPress({ x: this.touchStartX, y: this.touchStartY })
      }, this.longPressDelay)
    }
  }

  handleTouchMove(e) {
    // Cancel long press if user moves
    if (this.longPressTimer) {
      clearTimeout(this.longPressTimer)
      this.longPressTimer = null
    }
  }

  handleTouchEnd(e) {
    // Cancel long press
    if (this.longPressTimer) {
      clearTimeout(this.longPressTimer)
      this.longPressTimer = null
    }

    const touch = e.changedTouches[0]
    this.touchEndX = touch.clientX
    this.touchEndY = touch.clientY

    this.detectSwipe()
  }

  detectSwipe() {
    const deltaX = this.touchEndX - this.touchStartX
    const deltaY = this.touchEndY - this.touchStartY
    const absDeltaX = Math.abs(deltaX)
    const absDeltaY = Math.abs(deltaY)

    // Horizontal swipe
    if (absDeltaX > this.threshold && absDeltaX > absDeltaY) {
      if (deltaX > 0) {
        this.onSwipeRight?.({ deltaX, deltaY })
      } else {
        this.onSwipeLeft?.({ deltaX, deltaY })
      }
    }

    // Vertical swipe
    if (absDeltaY > this.threshold && absDeltaY > absDeltaX) {
      if (deltaY > 0) {
        this.onSwipeDown?.({ deltaX, deltaY })
      } else {
        this.onSwipeUp?.({ deltaX, deltaY })
      }
    }
  }

  destroy() {
    if (this.longPressTimer) {
      clearTimeout(this.longPressTimer)
    }
  }
}
```

---

## 3.3 Responsive Utilities

**File**: `app/javascript/maps_v2/utils/responsive.js`

```javascript
/**
 * Responsive breakpoint utilities
 */

export const BREAKPOINTS = {
  mobile: 768,
  tablet: 1024,
  desktop: 1280
}

/**
 * Check if viewport is mobile
 * @returns {boolean}
 */
export function isMobile() {
  return window.innerWidth < BREAKPOINTS.mobile
}

/**
 * Check if viewport is tablet
 * @returns {boolean}
 */
export function isTablet() {
  return window.innerWidth >= BREAKPOINTS.mobile && window.innerWidth < BREAKPOINTS.tablet
}

/**
 * Check if viewport is desktop
 * @returns {boolean}
 */
export function isDesktop() {
  return window.innerWidth >= BREAKPOINTS.desktop
}

/**
 * Get current breakpoint name
 * @returns {'mobile'|'tablet'|'desktop'}
 */
export function getCurrentBreakpoint() {
  if (isMobile()) return 'mobile'
  if (isTablet()) return 'tablet'
  return 'desktop'
}

/**
 * Watch for breakpoint changes
 * @param {Function} callback - Called with breakpoint name
 * @returns {Function} Cleanup function
 */
export function watchBreakpoint(callback) {
  let currentBreakpoint = getCurrentBreakpoint()

  const handler = () => {
    const newBreakpoint = getCurrentBreakpoint()
    if (newBreakpoint !== currentBreakpoint) {
      currentBreakpoint = newBreakpoint
      callback(newBreakpoint)
    }
  }

  window.addEventListener('resize', handler)

  // Cleanup
  return () => window.removeEventListener('resize', handler)
}
```

---

## 3.4 Bottom Sheet Controller

Mobile-first sliding panel with snap points.

**File**: `app/javascript/maps_v2/controllers/bottom_sheet_controller.js`

```javascript
import { Controller } from '@hotwired/stimulus'
import { GestureDetector } from '../utils/gestures'
import { isMobile } from '../utils/responsive'

/**
 * Bottom sheet controller for mobile UI
 * Supports swipe gestures and snap points
 */
export default class extends Controller {
  static targets = ['sheet', 'handle']

  static values = {
    snapPoints: { type: Array, default: [0.15, 0.5, 0.9] }, // Percentages of viewport height
    currentSnap: { type: Number, default: 1 } // Index of current snap point
  }

  connect() {
    // Only enable on mobile
    if (!isMobile()) {
      this.element.style.display = 'none'
      return
    }

    this.isDragging = false
    this.startY = 0
    this.currentY = 0
    this.sheetHeight = 0

    this.setupGestures()
    this.snapToPoint(this.currentSnapValue)
  }

  disconnect() {
    this.gestureDetector?.destroy()
  }

  /**
   * Setup touch gestures
   */
  setupGestures() {
    this.gestureDetector = new GestureDetector(this.sheetTarget, {
      onSwipeUp: () => this.snapToNext(),
      onSwipeDown: () => this.snapToPrevious()
    })

    // Add drag handler for more control
    this.handleTarget.addEventListener('touchstart', this.onTouchStart.bind(this))
    this.handleTarget.addEventListener('touchmove', this.onTouchMove.bind(this))
    this.handleTarget.addEventListener('touchend', this.onTouchEnd.bind(this))
  }

  /**
   * Touch start handler
   */
  onTouchStart(e) {
    this.isDragging = true
    this.startY = e.touches[0].clientY
    this.sheetHeight = this.sheetTarget.offsetHeight

    this.sheetTarget.style.transition = 'none'
  }

  /**
   * Touch move handler
   */
  onTouchMove(e) {
    if (!this.isDragging) return

    this.currentY = e.touches[0].clientY
    const deltaY = this.currentY - this.startY

    // Calculate new height
    const newHeight = this.sheetHeight - deltaY
    const viewportHeight = window.innerHeight
    const percentage = newHeight / viewportHeight

    // Clamp between min and max snap points
    const minSnap = this.snapPointsValue[0]
    const maxSnap = this.snapPointsValue[this.snapPointsValue.length - 1]

    if (percentage >= minSnap && percentage <= maxSnap) {
      this.sheetTarget.style.height = `${percentage * 100}vh`
    }
  }

  /**
   * Touch end handler
   */
  onTouchEnd() {
    if (!this.isDragging) return

    this.isDragging = false
    this.sheetTarget.style.transition = ''

    // Find nearest snap point
    const viewportHeight = window.innerHeight
    const currentHeight = this.sheetTarget.offsetHeight
    const currentPercentage = currentHeight / viewportHeight

    const nearestSnapIndex = this.findNearestSnapPoint(currentPercentage)
    this.snapToPoint(nearestSnapIndex)
  }

  /**
   * Find nearest snap point
   * @param {number} percentage - Current height percentage
   * @returns {number} Snap point index
   */
  findNearestSnapPoint(percentage) {
    let nearestIndex = 0
    let minDiff = Math.abs(this.snapPointsValue[0] - percentage)

    this.snapPointsValue.forEach((snap, index) => {
      const diff = Math.abs(snap - percentage)
      if (diff < minDiff) {
        minDiff = diff
        nearestIndex = index
      }
    })

    return nearestIndex
  }

  /**
   * Snap to specific point
   * @param {number} index - Snap point index
   */
  snapToPoint(index) {
    if (index < 0 || index >= this.snapPointsValue.length) return

    this.currentSnapValue = index
    const percentage = this.snapPointsValue[index]

    this.sheetTarget.style.height = `${percentage * 100}vh`

    // Dispatch event
    this.dispatch('snapped', {
      detail: { index, percentage }
    })
  }

  /**
   * Snap to next point (expand)
   */
  snapToNext() {
    const nextIndex = Math.min(
      this.currentSnapValue + 1,
      this.snapPointsValue.length - 1
    )
    this.snapToPoint(nextIndex)
  }

  /**
   * Snap to previous point (collapse)
   */
  snapToPrevious() {
    const prevIndex = Math.max(this.currentSnapValue - 1, 0)
    this.snapToPoint(prevIndex)
  }

  /**
   * Expand to full height
   */
  expand() {
    this.snapToPoint(this.snapPointsValue.length - 1)
  }

  /**
   * Collapse to minimum
   */
  collapse() {
    this.snapToPoint(0)
  }

  /**
   * Toggle between collapsed and half
   */
  toggle() {
    if (this.currentSnapValue === 0) {
      this.snapToPoint(1) // Half
    } else {
      this.collapse()
    }
  }
}
```

---

## 3.5 Settings Panel Controller

Map configuration and preferences.

**File**: `app/javascript/maps_v2/controllers/settings_panel_controller.js`

```javascript
import { Controller } from '@hotwired/stimulus'

/**
 * Settings panel controller
 * Manages map preferences and configuration
 */
export default class extends Controller {
  static targets = [
    'panel',
    'clusteringToggle',
    'clusterRadiusInput',
    'heatmapIntensityInput',
    'heatmapRadiusInput',
    'mapStyleSelect'
  ]

  static outlets = ['map']

  static values = {
    open: { type: Boolean, default: false }
  }

  connect() {
    this.loadSettings()
  }

  /**
   * Toggle settings panel
   */
  toggle() {
    this.openValue = !this.openValue
    this.panelTarget.classList.toggle('open', this.openValue)
  }

  /**
   * Open settings panel
   */
  open() {
    this.openValue = true
    this.panelTarget.classList.add('open')
  }

  /**
   * Close settings panel
   */
  close() {
    this.openValue = false
    this.panelTarget.classList.remove('open')
  }

  /**
   * Load settings from localStorage
   */
  loadSettings() {
    const settings = this.getStoredSettings()

    if (this.hasClusteringToggleTarget) {
      this.clusteringToggleTarget.checked = settings.clustering !== false
    }

    if (this.hasClusterRadiusInputTarget) {
      this.clusterRadiusInputTarget.value = settings.clusterRadius || 50
    }

    if (this.hasHeatmapIntensityInputTarget) {
      this.heatmapIntensityInputTarget.value = settings.heatmapIntensity || 1
    }

    if (this.hasHeatmapRadiusInputTarget) {
      this.heatmapRadiusInputTarget.value = settings.heatmapRadius || 20
    }

    if (this.hasMapStyleSelectTarget) {
      this.mapStyleSelectTarget.value = settings.mapStyle || 'positron'
    }
  }

  /**
   * Get stored settings
   * @returns {Object}
   */
  getStoredSettings() {
    const stored = localStorage.getItem('maps-v2-settings')
    return stored ? JSON.parse(stored) : {}
  }

  /**
   * Save settings to localStorage
   */
  saveSettings() {
    const settings = {
      clustering: this.hasClusteringToggleTarget ? this.clusteringToggleTarget.checked : true,
      clusterRadius: this.hasClusterRadiusInputTarget ? parseInt(this.clusterRadiusInputTarget.value) : 50,
      heatmapIntensity: this.hasHeatmapIntensityInputTarget ? parseFloat(this.heatmapIntensityInputTarget.value) : 1,
      heatmapRadius: this.hasHeatmapRadiusInputTarget ? parseInt(this.heatmapRadiusInputTarget.value) : 20,
      mapStyle: this.hasMapStyleSelectTarget ? this.mapStyleSelectTarget.value : 'positron'
    }

    localStorage.setItem('maps-v2-settings', JSON.stringify(settings))

    return settings
  }

  /**
   * Handle clustering toggle
   */
  toggleClustering() {
    const settings = this.saveSettings()

    if (this.hasMapOutlet) {
      // Recreate points layer with new clustering setting
      this.mapOutlet.loadMapData()
    }
  }

  /**
   * Handle cluster radius change
   */
  updateClusterRadius() {
    const settings = this.saveSettings()

    if (this.hasMapOutlet) {
      this.mapOutlet.loadMapData()
    }
  }

  /**
   * Handle heatmap intensity change
   */
  updateHeatmapIntensity() {
    const settings = this.saveSettings()

    if (this.hasMapOutlet && this.mapOutlet.heatmapLayer) {
      this.mapOutlet.heatmapLayer.setIntensity(settings.heatmapIntensity)
    }
  }

  /**
   * Handle heatmap radius change
   */
  updateHeatmapRadius() {
    const settings = this.saveSettings()

    if (this.hasMapOutlet && this.mapOutlet.heatmapLayer) {
      this.mapOutlet.heatmapLayer.setRadius(settings.heatmapRadius)
    }
  }

  /**
   * Handle map style change
   */
  changeMapStyle() {
    const settings = this.saveSettings()

    if (this.hasMapOutlet) {
      const styleUrls = {
        positron: 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
        'dark-matter': 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json',
        voyager: 'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json'
      }

      const styleUrl = styleUrls[settings.mapStyle] || styleUrls.positron
      this.mapOutlet.map.setStyle(styleUrl)

      // Reload layers after style change
      this.mapOutlet.map.once('styledata', () => {
        this.mapOutlet.loadMapData()
      })
    }
  }

  /**
   * Reset to defaults
   */
  resetToDefaults() {
    localStorage.removeItem('maps-v2-settings')
    this.loadSettings()

    if (this.hasMapOutlet) {
      this.mapOutlet.loadMapData()
    }
  }
}
```

---

## 3.6 Update Map Controller

Add heatmap layer and settings integration.

**File**: `app/javascript/maps_v2/controllers/map_controller.js` (update)

```javascript
// Add at top
import { HeatmapLayer } from '../layers/heatmap_layer'

// In connect() method, add:
connect() {
  this.initializeMap()
  this.initializeAPI()
  this.loadSettings() // NEW
  this.loadMapData()
}

// Add new method:
/**
 * Load settings from localStorage
 * NEW in Phase 3
 */
loadSettings() {
  const stored = localStorage.getItem('maps-v2-settings')
  this.settings = stored ? JSON.parse(stored) : {
    clustering: true,
    clusterRadius: 50,
    heatmapIntensity: 1,
    heatmapRadius: 20,
    mapStyle: 'positron'
  }
}

// Update loadMapData() to add heatmap:
async loadMapData() {
  this.showLoading()

  try {
    const points = await this.api.fetchAllPoints({
      start_at: this.startDateValue,
      end_at: this.endDateValue,
      onProgress: this.updateLoadingProgress.bind(this)
    })

    const pointsGeoJSON = pointsToGeoJSON(points)

    // Update points layer
    if (!this.pointsLayer) {
      this.pointsLayer = new PointsLayer(this.map, {
        clustering: this.settings.clustering,
        clusterRadius: this.settings.clusterRadius
      })

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

    // Update routes layer
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

    // NEW: Add heatmap layer
    if (!this.heatmapLayer) {
      this.heatmapLayer = new HeatmapLayer(this.map, {
        radius: this.settings.heatmapRadius,
        intensity: this.settings.heatmapIntensity,
        visible: false // Hidden by default
      })

      if (this.map.loaded()) {
        this.heatmapLayer.add(pointsGeoJSON)
      } else {
        this.map.on('load', () => {
          this.heatmapLayer.add(pointsGeoJSON)
        })
      }
    } else {
      this.heatmapLayer.update(pointsGeoJSON)
    }

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
```

---

## 3.7 Bottom Sheet Partial

**File**: `app/views/maps_v2/_bottom_sheet.html.erb`

```erb
<div data-controller="bottom-sheet"
     data-bottom-sheet-snap-points-value="[0.15, 0.5, 0.9]"
     data-bottom-sheet-current-snap-value="1"
     class="bottom-sheet">

  <!-- Handle (drag area) -->
  <div data-bottom-sheet-target="handle" class="bottom-sheet-handle">
    <div class="handle-bar"></div>
  </div>

  <!-- Content -->
  <div data-bottom-sheet-target="sheet" class="bottom-sheet-content">
    <div class="bottom-sheet-header">
      <h3>Map Layers</h3>
    </div>

    <div class="bottom-sheet-body">
      <!-- Layer controls -->
      <div class="layer-list">
        <button data-layer-controls-target="button"
                data-layer="points"
                data-action="click->layer-controls#toggleLayer"
                class="layer-item active">
          <span class="layer-icon">📍</span>
          <span class="layer-name">Points</span>
          <span class="layer-toggle"></span>
        </button>

        <button data-layer-controls-target="button"
                data-layer="routes"
                data-action="click->layer-controls#toggleLayer"
                class="layer-item active">
          <span class="layer-icon">🛣️</span>
          <span class="layer-name">Routes</span>
          <span class="layer-toggle"></span>
        </button>

        <button data-layer-controls-target="button"
                data-layer="heatmap"
                data-action="click->layer-controls#toggleLayer"
                class="layer-item">
          <span class="layer-icon">🔥</span>
          <span class="layer-name">Heatmap</span>
          <span class="layer-toggle"></span>
        </button>
      </div>
    </div>
  </div>
</div>

<style>
  .bottom-sheet {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: white;
    border-radius: 16px 16px 0 0;
    box-shadow: 0 -4px 12px rgba(0, 0, 0, 0.1);
    z-index: 100;
    height: 50vh;
    transition: height 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  }

  .bottom-sheet-handle {
    padding: 12px 0;
    cursor: grab;
    display: flex;
    justify-content: center;
  }

  .bottom-sheet-handle:active {
    cursor: grabbing;
  }

  .handle-bar {
    width: 40px;
    height: 4px;
    background: #d1d5db;
    border-radius: 2px;
  }

  .bottom-sheet-content {
    height: calc(100% - 40px);
    overflow-y: auto;
    overflow-x: hidden;
  }

  .bottom-sheet-header {
    padding: 0 20px 16px;
    border-bottom: 1px solid #e5e7eb;
  }

  .bottom-sheet-header h3 {
    margin: 0;
    font-size: 18px;
    font-weight: 600;
    color: #111827;
  }

  .bottom-sheet-body {
    padding: 16px 20px;
  }

  .layer-list {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .layer-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 16px;
    background: #f9fafb;
    border: 2px solid transparent;
    border-radius: 8px;
    font-size: 16px;
    cursor: pointer;
    transition: all 0.2s;
    width: 100%;
    text-align: left;
  }

  .layer-item:hover {
    background: #f3f4f6;
  }

  .layer-item.active {
    background: #eff6ff;
    border-color: #3b82f6;
  }

  .layer-icon {
    font-size: 20px;
  }

  .layer-name {
    flex: 1;
    font-weight: 500;
    color: #374151;
  }

  .layer-item.active .layer-name {
    color: #1e40af;
  }

  .layer-toggle {
    width: 44px;
    height: 24px;
    background: #d1d5db;
    border-radius: 12px;
    position: relative;
    transition: background 0.2s;
  }

  .layer-toggle::after {
    content: '';
    position: absolute;
    width: 20px;
    height: 20px;
    background: white;
    border-radius: 50%;
    top: 2px;
    left: 2px;
    transition: transform 0.2s;
  }

  .layer-item.active .layer-toggle {
    background: #3b82f6;
  }

  .layer-item.active .layer-toggle::after {
    transform: translateX(20px);
  }

  /* Desktop - hide bottom sheet */
  @media (min-width: 768px) {
    .bottom-sheet {
      display: none;
    }
  }
</style>
```

---

## 3.8 Settings Panel Partial

**File**: `app/views/maps_v2/_settings_panel.html.erb`

```erb
<div data-controller="settings-panel"
     data-settings-panel-map-outlet=".map-wrapper"
     class="settings-panel">

  <!-- Toggle button -->
  <button data-action="click->settings-panel#toggle"
          class="settings-toggle-btn"
          title="Settings">
    ⚙️
  </button>

  <!-- Panel -->
  <div data-settings-panel-target="panel" class="settings-panel-content">
    <div class="settings-header">
      <h3>Map Settings</h3>
      <button data-action="click->settings-panel#close"
              class="close-btn">
        ✕
      </button>
    </div>

    <div class="settings-body">
      <!-- Map Style -->
      <div class="setting-group">
        <label>Map Style</label>
        <select data-settings-panel-target="mapStyleSelect"
                data-action="change->settings-panel#changeMapStyle"
                class="setting-select">
          <option value="positron">Light</option>
          <option value="dark-matter">Dark</option>
          <option value="voyager">Voyager</option>
        </select>
      </div>

      <!-- Clustering -->
      <div class="setting-group">
        <label class="setting-checkbox">
          <input type="checkbox"
                 data-settings-panel-target="clusteringToggle"
                 data-action="change->settings-panel#toggleClustering"
                 checked>
          <span>Enable Point Clustering</span>
        </label>
      </div>

      <!-- Cluster Radius -->
      <div class="setting-group">
        <label>Cluster Radius</label>
        <input type="range"
               data-settings-panel-target="clusterRadiusInput"
               data-action="change->settings-panel#updateClusterRadius"
               min="20"
               max="100"
               value="50"
               class="setting-range">
        <span class="setting-value" data-settings-panel-target="clusterRadiusValue">50</span>
      </div>

      <!-- Heatmap Intensity -->
      <div class="setting-group">
        <label>Heatmap Intensity</label>
        <input type="range"
               data-settings-panel-target="heatmapIntensityInput"
               data-action="change->settings-panel#updateHeatmapIntensity"
               min="0.1"
               max="2"
               step="0.1"
               value="1"
               class="setting-range">
        <span class="setting-value" data-settings-panel-target="heatmapIntensityValue">1.0</span>
      </div>

      <!-- Heatmap Radius -->
      <div class="setting-group">
        <label>Heatmap Radius</label>
        <input type="range"
               data-settings-panel-target="heatmapRadiusInput"
               data-action="change->settings-panel#updateHeatmapRadius"
               min="10"
               max="50"
               value="20"
               class="setting-range">
        <span class="setting-value" data-settings-panel-target="heatmapRadiusValue">20</span>
      </div>

      <!-- Reset Button -->
      <button data-action="click->settings-panel#resetToDefaults"
              class="reset-btn">
        Reset to Defaults
      </button>
    </div>
  </div>
</div>

<style>
  .settings-toggle-btn {
    position: fixed;
    top: 16px;
    right: 16px;
    width: 44px;
    height: 44px;
    background: white;
    border: 2px solid #e5e7eb;
    border-radius: 8px;
    font-size: 20px;
    cursor: pointer;
    z-index: 50;
    transition: all 0.2s;
  }

  .settings-toggle-btn:hover {
    border-color: #3b82f6;
    box-shadow: 0 2px 8px rgba(59, 130, 246, 0.2);
  }

  .settings-panel-content {
    position: fixed;
    top: 0;
    right: -320px;
    width: 320px;
    height: 100vh;
    background: white;
    box-shadow: -4px 0 12px rgba(0, 0, 0, 0.1);
    z-index: 60;
    transition: right 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    overflow-y: auto;
  }

  .settings-panel-content.open {
    right: 0;
  }

  .settings-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 20px;
    border-bottom: 1px solid #e5e7eb;
  }

  .settings-header h3 {
    margin: 0;
    font-size: 18px;
    font-weight: 600;
    color: #111827;
  }

  .close-btn {
    width: 32px;
    height: 32px;
    background: transparent;
    border: none;
    font-size: 20px;
    cursor: pointer;
    color: #6b7280;
    transition: color 0.2s;
  }

  .close-btn:hover {
    color: #111827;
  }

  .settings-body {
    padding: 20px;
  }

  .setting-group {
    margin-bottom: 24px;
  }

  .setting-group label {
    display: block;
    margin-bottom: 8px;
    font-size: 14px;
    font-weight: 500;
    color: #374151;
  }

  .setting-select {
    width: 100%;
    padding: 8px 12px;
    border: 1px solid #d1d5db;
    border-radius: 6px;
    font-size: 14px;
  }

  .setting-checkbox {
    display: flex;
    align-items: center;
    gap: 8px;
    cursor: pointer;
  }

  .setting-checkbox input[type="checkbox"] {
    width: 20px;
    height: 20px;
    cursor: pointer;
  }

  .setting-range {
    width: calc(100% - 60px);
    margin-right: 12px;
  }

  .setting-value {
    display: inline-block;
    width: 48px;
    text-align: right;
    font-size: 14px;
    color: #6b7280;
  }

  .reset-btn {
    width: 100%;
    padding: 10px;
    background: #f3f4f6;
    border: 1px solid #d1d5db;
    border-radius: 6px;
    font-size: 14px;
    font-weight: 500;
    color: #374151;
    cursor: pointer;
    transition: all 0.2s;
  }

  .reset-btn:hover {
    background: #e5e7eb;
  }

  /* Mobile adjustments */
  @media (max-width: 768px) {
    .settings-panel-content {
      width: 100%;
      right: -100%;
    }

    .settings-panel-content.open {
      right: 0;
    }
  }
</style>
```

---

## 3.9 Updated View Template

**File**: `app/views/maps_v2/index.html.erb` (update - add bottom sheet and settings)

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

    <!-- Layer Controls (desktop only) -->
    <div class="layer-controls desktop-only">
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

      <button data-layer-controls-target="button"
              data-layer="heatmap"
              data-action="click->layer-controls#toggleLayer"
              class="layer-button"
              aria-pressed="false">
        Heatmap
      </button>
    </div>
  </div>

  <!-- Date Navigation Panel (desktop) -->
  <div class="controls-panel desktop-only">
    <!-- [Same as Phase 2] -->
  </div>

  <!-- NEW: Bottom Sheet (mobile only) -->
  <%= render 'maps_v2/bottom_sheet' %>

  <!-- NEW: Settings Panel -->
  <%= render 'maps_v2/settings_panel' %>
</div>

<style>
  /* Add responsive utilities */
  .desktop-only {
    display: block;
  }

  @media (max-width: 768px) {
    .desktop-only {
      display: none;
    }

    .controls-panel {
      display: none;
    }
  }
</style>
```

---

## 🧪 E2E Tests

**File**: `e2e/v2/phase-3-mobile.spec.ts`

```typescript
import { test, expect, devices } from '@playwright/test'
import { login, waitForMap } from './helpers/setup'

test.describe('Phase 3: Heatmap + Mobile UI', () => {
  test.beforeEach(async ({ page }) => {
    await login(page)
    await page.goto('/maps_v2')
    await waitForMap(page)
  })

  test.describe('Heatmap Layer', () => {
    test('heatmap layer exists', async ({ page }) => {
      const hasHeatmap = await page.evaluate(() => {
        const map = window.mapInstance
        return map?.getLayer('heatmap') !== undefined
      })

      expect(hasHeatmap).toBe(true)
    })

    test('heatmap toggle works', async ({ page }) => {
      // Click heatmap button (desktop)
      const heatmapButton = page.locator('button[data-layer="heatmap"]')

      if (await heatmapButton.isVisible()) {
        await heatmapButton.click()

        const isVisible = await page.evaluate(() => {
          const map = window.mapInstance
          return map?.getLayoutProperty('heatmap', 'visibility') === 'visible'
        })

        expect(isVisible).toBe(true)
      }
    })
  })

  test.describe('Settings Panel', () => {
    test('settings panel opens and closes', async ({ page }) => {
      const settingsBtn = page.locator('.settings-toggle-btn')
      await settingsBtn.click()

      const panel = page.locator('.settings-panel-content')
      await expect(panel).toHaveClass(/open/)

      const closeBtn = page.locator('.close-btn')
      await closeBtn.click()

      await expect(panel).not.toHaveClass(/open/)
    })

    test('map style can be changed', async ({ page }) => {
      await page.click('.settings-toggle-btn')

      const styleSelect = page.locator('[data-settings-panel-target="mapStyleSelect"]')
      await styleSelect.selectOption('dark-matter')

      // Wait for style to load
      await page.waitForTimeout(1000)

      // Check localStorage
      const savedStyle = await page.evaluate(() => {
        const settings = JSON.parse(localStorage.getItem('maps-v2-settings') || '{}')
        return settings.mapStyle
      })

      expect(savedStyle).toBe('dark-matter')
    })

    test('clustering can be toggled', async ({ page }) => {
      await page.click('.settings-toggle-btn')

      const clusterToggle = page.locator('[data-settings-panel-target="clusteringToggle"]')
      await clusterToggle.click()

      // Wait for reload
      await waitForMap(page)

      // Check localStorage
      const clustering = await page.evaluate(() => {
        const settings = JSON.parse(localStorage.getItem('maps-v2-settings') || '{}')
        return settings.clustering
      })

      expect(clustering).toBe(false)
    })

    test('heatmap intensity slider works', async ({ page }) => {
      await page.click('.settings-toggle-btn')

      const intensitySlider = page.locator('[data-settings-panel-target="heatmapIntensityInput"]')
      await intensitySlider.fill('1.5')

      const savedIntensity = await page.evaluate(() => {
        const settings = JSON.parse(localStorage.getItem('maps-v2-settings') || '{}')
        return settings.heatmapIntensity
      })

      expect(savedIntensity).toBe(1.5)
    })
  })

  test.describe('Mobile UI', () => {
    test.use({ ...devices['iPhone 12'] })

    test('bottom sheet is visible on mobile', async ({ page }) => {
      await page.goto('/maps_v2')
      await waitForMap(page)

      const bottomSheet = page.locator('.bottom-sheet')
      await expect(bottomSheet).toBeVisible()
    })

    test('bottom sheet can be swiped', async ({ page }) => {
      await page.goto('/maps_v2')
      await waitForMap(page)

      const bottomSheet = page.locator('.bottom-sheet')
      const initialHeight = await bottomSheet.evaluate(el =>
        window.getComputedStyle(el).height
      )

      // Swipe up on handle
      const handle = page.locator('.bottom-sheet-handle')
      await handle.hover()

      // Simulate swipe up
      await page.touchscreen.tap(200, 500)
      await page.touchscreen.tap(200, 200)

      await page.waitForTimeout(500)

      const newHeight = await bottomSheet.evaluate(el =>
        window.getComputedStyle(el).height
      )

      // Height should have changed
      expect(newHeight).not.toBe(initialHeight)
    })

    test('layer controls in bottom sheet work', async ({ page }) => {
      await page.goto('/maps_v2')
      await waitForMap(page)

      // Find points button in bottom sheet
      const pointsButton = page.locator('.bottom-sheet .layer-item[data-layer="points"]')

      if (await pointsButton.isVisible()) {
        await pointsButton.click()

        await expect(pointsButton).not.toHaveClass(/active/)
      }
    })
  })

  test.describe('Responsive Design', () => {
    test('desktop shows layer controls', async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 720 })
      await page.goto('/maps_v2')
      await waitForMap(page)

      const layerControls = page.locator('.layer-controls.desktop-only')
      await expect(layerControls).toBeVisible()

      const bottomSheet = page.locator('.bottom-sheet')
      // Bottom sheet should be hidden on desktop
      await expect(bottomSheet).toHaveCSS('display', 'none')
    })

    test('mobile hides desktop controls', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 })
      await page.goto('/maps_v2')
      await waitForMap(page)

      const desktopControls = page.locator('.layer-controls.desktop-only')
      await expect(desktopControls).toHaveCSS('display', 'none')

      const bottomSheet = page.locator('.bottom-sheet')
      await expect(bottomSheet).toBeVisible()
    })
  })

  test.describe('Regression Tests', () => {
    test('points layer still works', async ({ page }) => {
      const hasPoints = await page.evaluate(() => {
        const map = window.mapInstance
        const source = map?.getSource('points-source')
        return source && source._data?.features?.length > 0
      })

      expect(hasPoints).toBe(true)
    })

    test('routes layer still works', async ({ page }) => {
      const hasRoutes = await page.evaluate(() => {
        const map = window.mapInstance
        const source = map?.getSource('routes-source')
        return source && source._data?.features?.length > 0
      })

      expect(hasRoutes).toBe(true)
    })

    test('date navigation still works', async ({ page }) => {
      const nextDayBtn = page.locator('button[title="Next Day"]')

      if (await nextDayBtn.isVisible()) {
        await nextDayBtn.click()
        await waitForMap(page)
      }
    })
  })
})
```

---

## ✅ Phase 3 Completion Checklist

### Implementation
- [ ] Created heatmap_layer.js
- [ ] Created bottom_sheet_controller.js
- [ ] Created settings_panel_controller.js
- [ ] Created gestures.js
- [ ] Created responsive.js
- [ ] Updated map_controller.js
- [ ] Created bottom sheet partial
- [ ] Created settings panel partial
- [ ] Updated main view template

### Functionality
- [ ] Heatmap renders correctly
- [ ] Bottom sheet works on mobile
- [ ] Swipe gestures functional
- [ ] Settings panel opens/closes
- [ ] Settings persist to localStorage
- [ ] Map style changes work
- [ ] Clustering toggle works
- [ ] Responsive breakpoints work

### Testing
- [ ] All Phase 3 E2E tests pass
- [ ] Phase 1 tests still pass (regression)
- [ ] Phase 2 tests still pass (regression)
- [ ] Manual mobile testing complete
- [ ] Manual desktop testing complete

### Performance
- [ ] Heatmap performs well with large datasets
- [ ] Bottom sheet animations smooth (60fps)
- [ ] Settings changes apply instantly
- [ ] No performance regression

---

## 🚀 Deployment

```bash
git checkout -b maps-v2-phase-3
git add app/javascript/maps_v2/ app/views/maps_v2/ e2e/v2/
git commit -m "feat: Maps V2 Phase 3 - Heatmap and mobile UI"

# Run all tests (regression)
npx playwright test e2e/v2/phase-1-mvp.spec.ts
npx playwright test e2e/v2/phase-2-routes.spec.ts
npx playwright test e2e/v2/phase-3-mobile.spec.ts

# Deploy to staging
git push origin maps-v2-phase-3
```

---

## 🎉 What's Next?

**Phase 4**: Add visits and photos layers with search/filter functionality.

**User Feedback**: Get mobile users to test the bottom sheet and gestures!
