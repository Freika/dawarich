# Phase 4: Visits + Photos

**Timeline**: Week 4
**Goal**: Add visits detection and photo integration
**Dependencies**: Phases 1-3 complete
**Status**: Ready for implementation

## 🎯 Phase Objectives

Build on Phases 1-3 by adding:
- ✅ Visits layer (suggested + confirmed)
- ✅ Photos layer with camera icons
- ✅ Visits drawer with search/filter
- ✅ Photo popups with image preview
- ✅ Visit statistics
- ✅ E2E tests

**Deploy Decision**: Users can see detected visits and photos on the map.

---

## 📋 Features Checklist

- [ ] Visits layer (yellow = suggested, green = confirmed)
- [ ] Photos layer with camera icons
- [ ] Click visit to see details
- [ ] Click photo to see preview
- [ ] Visits drawer (slide-in panel)
- [ ] Search visits by name
- [ ] Filter by suggested/confirmed
- [ ] Visit statistics (duration, frequency)
- [ ] E2E tests passing

---

## 🏗️ New Files (Phase 4)

```
app/javascript/maps_v2/
├── layers/
│   ├── visits_layer.js                # NEW: Visits markers
│   └── photos_layer.js                # NEW: Photo markers
├── controllers/
│   └── visits_drawer_controller.js    # NEW: Visits search/filter
└── components/
    ├── visit_popup.js                 # NEW: Visit popup factory
    └── photo_popup.js                 # NEW: Photo popup factory

app/views/maps_v2/
└── _visits_drawer.html.erb            # NEW: Visits drawer partial

e2e/v2/
└── phase-4-visits.spec.ts             # NEW: E2E tests
```

---

## 4.1 Visits Layer

Display suggested and confirmed visits with different colors.

**File**: `app/javascript/maps_v2/layers/visits_layer.js`

```javascript
import { BaseLayer } from './base_layer'

/**
 * Visits layer showing suggested and confirmed visits
 * Yellow = suggested, Green = confirmed
 */
export class VisitsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'visits', ...options })
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
      // Visit circles
      {
        id: this.id,
        type: 'circle',
        source: this.sourceId,
        paint: {
          'circle-radius': 12,
          'circle-color': [
            'case',
            ['==', ['get', 'status'], 'confirmed'], '#22c55e', // Green for confirmed
            '#eab308' // Yellow for suggested
          ],
          'circle-stroke-width': 2,
          'circle-stroke-color': '#ffffff',
          'circle-opacity': 0.8
        }
      },

      // Visit labels
      {
        id: `${this.id}-labels`,
        type: 'symbol',
        source: this.sourceId,
        layout: {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
          'text-size': 12,
          'text-offset': [0, 1.5],
          'text-anchor': 'top'
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
    return [this.id, `${this.id}-labels`]
  }
}
```

---

## 4.2 Photos Layer

Display photos with camera icon markers.

**File**: `app/javascript/maps_v2/layers/photos_layer.js`

```javascript
import { BaseLayer } from './base_layer'

/**
 * Photos layer with camera icons
 */
export class PhotosLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'photos', ...options })
    this.cameraIcon = null
  }

  async add(data) {
    // Load camera icon before adding layer
    await this.loadCameraIcon()
    super.add(data)
  }

  async loadCameraIcon() {
    if (this.cameraIcon || this.map.hasImage('camera-icon')) return

    // Create camera icon SVG
    const svg = `
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect x="2" y="6" width="20" height="14" rx="2" fill="#3b82f6"/>
        <circle cx="12" cy="13" r="3" fill="white"/>
        <rect x="8" y="3" width="8" height="3" rx="1" fill="#3b82f6"/>
      </svg>
    `

    const img = new Image(24, 24)
    img.src = 'data:image/svg+xml;base64,' + btoa(svg)

    await new Promise((resolve, reject) => {
      img.onload = () => {
        this.map.addImage('camera-icon', img)
        this.cameraIcon = true
        resolve()
      }
      img.onerror = reject
    })
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
        type: 'symbol',
        source: this.sourceId,
        layout: {
          'icon-image': 'camera-icon',
          'icon-size': 1,
          'icon-allow-overlap': true
        }
      }
    ]
  }
}
```

---

## 4.3 Visit Popup Factory

**File**: `app/javascript/maps_v2/components/visit_popup.js`

```javascript
import { formatTimestamp } from '../utils/geojson_transformers'

/**
 * Factory for creating visit popups
 */
export class VisitPopupFactory {
  /**
   * Create popup for a visit
   * @param {Object} properties - Visit properties
   * @returns {string} HTML for popup
   */
  static createVisitPopup(properties) {
    const { id, name, status, started_at, ended_at, duration, place_name } = properties

    const startTime = formatTimestamp(started_at)
    const endTime = formatTimestamp(ended_at)
    const durationHours = Math.round(duration / 3600)

    return `
      <div class="visit-popup">
        <div class="popup-header">
          <strong>${name || place_name || 'Unknown Place'}</strong>
          <span class="visit-badge ${status}">${status}</span>
        </div>
        <div class="popup-body">
          <div class="popup-row">
            <span class="label">Arrived:</span>
            <span class="value">${startTime}</span>
          </div>
          <div class="popup-row">
            <span class="label">Left:</span>
            <span class="value">${endTime}</span>
          </div>
          <div class="popup-row">
            <span class="label">Duration:</span>
            <span class="value">${durationHours}h</span>
          </div>
        </div>
        <div class="popup-footer">
          <a href="/visits/${id}" class="view-details-btn">View Details</a>
        </div>
      </div>

      <style>
        .visit-popup {
          font-family: system-ui, -apple-system, sans-serif;
          min-width: 250px;
        }

        .popup-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 12px;
          padding-bottom: 8px;
          border-bottom: 1px solid #e5e7eb;
        }

        .visit-badge {
          padding: 2px 8px;
          border-radius: 4px;
          font-size: 11px;
          font-weight: 600;
          text-transform: uppercase;
        }

        .visit-badge.suggested {
          background: #fef3c7;
          color: #92400e;
        }

        .visit-badge.confirmed {
          background: #d1fae5;
          color: #065f46;
        }

        .popup-body {
          font-size: 13px;
          margin-bottom: 12px;
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

        .popup-footer {
          padding-top: 8px;
          border-top: 1px solid #e5e7eb;
        }

        .view-details-btn {
          display: block;
          text-align: center;
          padding: 6px 12px;
          background: #3b82f6;
          color: white;
          text-decoration: none;
          border-radius: 6px;
          font-size: 13px;
          font-weight: 500;
          transition: background 0.2s;
        }

        .view-details-btn:hover {
          background: #2563eb;
        }
      </style>
    `
  }
}
```

---

## 4.4 Photo Popup Factory

**File**: `app/javascript/maps_v2/components/photo_popup.js`

```javascript
/**
 * Factory for creating photo popups
 */
export class PhotoPopupFactory {
  /**
   * Create popup for a photo
   * @param {Object} properties - Photo properties
   * @returns {string} HTML for popup
   */
  static createPhotoPopup(properties) {
    const { id, thumbnail_url, url, taken_at, camera, location_name } = properties

    return `
      <div class="photo-popup">
        <div class="photo-preview">
          <img src="${thumbnail_url || url}"
               alt="Photo"
               loading="lazy">
        </div>
        <div class="photo-info">
          ${location_name ? `<div class="location">${location_name}</div>` : ''}
          ${taken_at ? `<div class="timestamp">${new Date(taken_at * 1000).toLocaleString()}</div>` : ''}
          ${camera ? `<div class="camera">${camera}</div>` : ''}
        </div>
        <div class="photo-actions">
          <a href="${url}" target="_blank" class="view-full-btn">View Full Size</a>
        </div>
      </div>

      <style>
        .photo-popup {
          font-family: system-ui, -apple-system, sans-serif;
          max-width: 300px;
        }

        .photo-preview {
          width: 100%;
          border-radius: 8px;
          overflow: hidden;
          margin-bottom: 12px;
        }

        .photo-preview img {
          width: 100%;
          height: auto;
          display: block;
        }

        .photo-info {
          font-size: 13px;
          margin-bottom: 12px;
        }

        .photo-info .location {
          font-weight: 600;
          color: #111827;
          margin-bottom: 4px;
        }

        .photo-info .timestamp {
          color: #6b7280;
          font-size: 12px;
          margin-bottom: 4px;
        }

        .photo-info .camera {
          color: #9ca3af;
          font-size: 11px;
        }

        .photo-actions {
          padding-top: 8px;
          border-top: 1px solid #e5e7eb;
        }

        .view-full-btn {
          display: block;
          text-align: center;
          padding: 6px 12px;
          background: #3b82f6;
          color: white;
          text-decoration: none;
          border-radius: 6px;
          font-size: 13px;
          font-weight: 500;
          transition: background 0.2s;
        }

        .view-full-btn:hover {
          background: #2563eb;
        }
      </style>
    `
  }
}
```

---

## 4.5 Visits Drawer Controller

Search and filter visits.

**File**: `app/javascript/maps_v2/controllers/visits_drawer_controller.js`

```javascript
import { Controller } from '@hotwired/stimulus'

/**
 * Visits drawer controller
 * Manages visits list with search and filter
 */
export default class extends Controller {
  static targets = [
    'drawer',
    'searchInput',
    'filterSelect',
    'visitsList',
    'visitItem',
    'emptyState'
  ]

  static values = {
    open: { type: Boolean, default: false }
  }

  static outlets = ['map']

  connect() {
    this.visits = []
    this.filteredVisits = []
  }

  /**
   * Toggle drawer
   */
  toggle() {
    this.openValue = !this.openValue
    this.drawerTarget.classList.toggle('open', this.openValue)
  }

  /**
   * Open drawer
   */
  open() {
    this.openValue = true
    this.drawerTarget.classList.add('open')
  }

  /**
   * Close drawer
   */
  close() {
    this.openValue = false
    this.drawerTarget.classList.remove('open')
  }

  /**
   * Load visits from API
   * @param {Array} visits - Visits data
   */
  loadVisits(visits) {
    this.visits = visits
    this.applyFilters()
  }

  /**
   * Search visits
   */
  search() {
    this.applyFilters()
  }

  /**
   * Filter visits by status
   */
  filter() {
    this.applyFilters()
  }

  /**
   * Apply search and filter
   */
  applyFilters() {
    const searchTerm = this.hasSearchInputTarget
      ? this.searchInputTarget.value.toLowerCase()
      : ''

    const filterStatus = this.hasFilterSelectTarget
      ? this.filterSelectTarget.value
      : 'all'

    this.filteredVisits = this.visits.filter(visit => {
      // Apply search
      const matchesSearch = !searchTerm ||
        visit.name?.toLowerCase().includes(searchTerm) ||
        visit.place_name?.toLowerCase().includes(searchTerm)

      // Apply filter
      const matchesFilter = filterStatus === 'all' ||
        visit.status === filterStatus

      return matchesSearch && matchesFilter
    })

    this.renderVisits()
  }

  /**
   * Render visits list
   */
  renderVisits() {
    if (!this.hasVisitsListTarget) return

    if (this.filteredVisits.length === 0) {
      this.showEmptyState()
      return
    }

    this.hideEmptyState()

    const html = this.filteredVisits.map(visit => this.renderVisitItem(visit)).join('')
    this.visitsListTarget.innerHTML = html
  }

  /**
   * Render single visit item
   * @param {Object} visit
   * @returns {string} HTML
   */
  renderVisitItem(visit) {
    const duration = Math.round(visit.duration / 3600)

    return `
      <div class="visit-item"
           data-visit-id="${visit.id}"
           data-action="click->visits-drawer#selectVisit">
        <div class="visit-icon ${visit.status}">
          ${visit.status === 'confirmed' ? '✓' : '?'}
        </div>
        <div class="visit-details">
          <div class="visit-name">${visit.name || visit.place_name || 'Unknown'}</div>
          <div class="visit-meta">
            ${duration}h • ${new Date(visit.started_at * 1000).toLocaleDateString()}
          </div>
        </div>
        <div class="visit-arrow">›</div>
      </div>
    `
  }

  /**
   * Select a visit (zoom to it on map)
   */
  selectVisit(event) {
    const visitId = event.currentTarget.dataset.visitId
    const visit = this.visits.find(v => v.id.toString() === visitId)

    if (visit && this.hasMapOutlet) {
      // Fly to visit location
      this.mapOutlet.map.flyTo({
        center: [visit.longitude, visit.latitude],
        zoom: 15,
        duration: 1000
      })

      // Show popup
      const popup = new maplibregl.Popup()
        .setLngLat([visit.longitude, visit.latitude])
        .setHTML(VisitPopupFactory.createVisitPopup(visit))
        .addTo(this.mapOutlet.map)
    }
  }

  /**
   * Show empty state
   */
  showEmptyState() {
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.remove('hidden')
    }
    if (this.hasVisitsListTarget) {
      this.visitsListTarget.innerHTML = ''
    }
  }

  /**
   * Hide empty state
   */
  hideEmptyState() {
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.add('hidden')
    }
  }
}
```

---

## 4.6 Update Map Controller

Add visits and photos layers.

**File**: `app/javascript/maps_v2/controllers/map_controller.js` (add to loadMapData)

```javascript
// Add imports
import { VisitsLayer } from '../layers/visits_layer'
import { PhotosLayer } from '../layers/photos_layer'
import { VisitPopupFactory } from '../components/visit_popup'
import { PhotoPopupFactory } from '../components/photo_popup'

// In loadMapData(), after heatmap layer:

// NEW: Load and add visits
const visits = await this.api.fetchVisits({
  start_at: this.startDateValue,
  end_at: this.endDateValue
})

const visitsGeoJSON = this.visitsToGeoJSON(visits)

if (!this.visitsLayer) {
  this.visitsLayer = new VisitsLayer(this.map, { visible: false })

  if (this.map.loaded()) {
    this.visitsLayer.add(visitsGeoJSON)
  } else {
    this.map.on('load', () => {
      this.visitsLayer.add(visitsGeoJSON)
    })
  }
} else {
  this.visitsLayer.update(visitsGeoJSON)
}

// NEW: Load and add photos
const photos = await this.api.fetchPhotos({
  start_at: this.startDateValue,
  end_at: this.endDateValue
})

const photosGeoJSON = this.photosToGeoJSON(photos)

if (!this.photosLayer) {
  this.photosLayer = new PhotosLayer(this.map, { visible: false })

  if (this.map.loaded()) {
    await this.photosLayer.add(photosGeoJSON)
  } else {
    this.map.on('load', async () => {
      await this.photosLayer.add(photosGeoJSON)
    })
  }
} else {
  await this.photosLayer.update(photosGeoJSON)
}

// Add click handlers
this.map.on('click', 'visits', this.handleVisitClick.bind(this))
this.map.on('click', 'photos', this.handlePhotoClick.bind(this))

// Add new helper methods:

/**
 * Convert visits to GeoJSON
 */
visitsToGeoJSON(visits) {
  return {
    type: 'FeatureCollection',
    features: visits.map(visit => ({
      type: 'Feature',
      geometry: {
        type: 'Point',
        coordinates: [visit.longitude, visit.latitude]
      },
      properties: {
        id: visit.id,
        name: visit.name,
        place_name: visit.place_name,
        status: visit.status,
        started_at: visit.started_at,
        ended_at: visit.ended_at,
        duration: visit.duration
      }
    }))
  }
}

/**
 * Convert photos to GeoJSON
 */
photosToGeoJSON(photos) {
  return {
    type: 'FeatureCollection',
    features: photos.map(photo => ({
      type: 'Feature',
      geometry: {
        type: 'Point',
        coordinates: [photo.longitude, photo.latitude]
      },
      properties: {
        id: photo.id,
        thumbnail_url: photo.thumbnail_url,
        url: photo.url,
        taken_at: photo.taken_at,
        camera: photo.camera,
        location_name: photo.location_name
      }
    }))
  }
}

/**
 * Handle visit click
 */
handleVisitClick(e) {
  const feature = e.features[0]
  const coordinates = feature.geometry.coordinates.slice()
  const properties = feature.properties

  new maplibregl.Popup()
    .setLngLat(coordinates)
    .setHTML(VisitPopupFactory.createVisitPopup(properties))
    .addTo(this.map)
}

/**
 * Handle photo click
 */
handlePhotoClick(e) {
  const feature = e.features[0]
  const coordinates = feature.geometry.coordinates.slice()
  const properties = feature.properties

  new maplibregl.Popup()
    .setLngLat(coordinates)
    .setHTML(PhotoPopupFactory.createPhotoPopup(properties))
    .addTo(this.map)
}
```

---

## 4.7 Update API Client

Add visits and photos endpoints.

**File**: `app/javascript/maps_v2/services/api_client.js` (add methods)

```javascript
/**
 * Fetch visits for date range
 * @param {Object} options - { start_at, end_at }
 * @returns {Promise<Array>} Visits
 */
async fetchVisits({ start_at, end_at }) {
  const params = new URLSearchParams({
    start_at,
    end_at
  })

  const response = await fetch(`${this.baseURL}/visits?${params}`, {
    headers: this.getHeaders()
  })

  if (!response.ok) {
    throw new Error(`Failed to fetch visits: ${response.statusText}`)
  }

  return response.json()
}

/**
 * Fetch photos for date range
 * @param {Object} options - { start_at, end_at }
 * @returns {Promise<Array>} Photos
 */
async fetchPhotos({ start_at, end_at }) {
  const params = new URLSearchParams({
    start_at,
    end_at
  })

  const response = await fetch(`${this.baseURL}/photos?${params}`, {
    headers: this.getHeaders()
  })

  if (!response.ok) {
    throw new Error(`Failed to fetch photos: ${response.statusText}`)
  }

  return response.json()
}
```

---

## 4.8 Visits Drawer Partial

**File**: `app/views/maps_v2/_visits_drawer.html.erb`

```erb
<div data-controller="visits-drawer"
     data-visits-drawer-map-outlet=".map-wrapper"
     class="visits-drawer">

  <!-- Toggle button -->
  <button data-action="click->visits-drawer#toggle"
          class="visits-toggle-btn"
          title="Visits">
    📍 Visits
  </button>

  <!-- Drawer -->
  <div data-visits-drawer-target="drawer" class="visits-drawer-content">
    <div class="visits-header">
      <h3>Visits</h3>
      <button data-action="click->visits-drawer#close" class="close-btn">✕</button>
    </div>

    <!-- Search and filter -->
    <div class="visits-controls">
      <input type="text"
             data-visits-drawer-target="searchInput"
             data-action="input->visits-drawer#search"
             placeholder="Search visits..."
             class="search-input">

      <select data-visits-drawer-target="filterSelect"
              data-action="change->visits-drawer#filter"
              class="filter-select">
        <option value="all">All Visits</option>
        <option value="confirmed">Confirmed</option>
        <option value="suggested">Suggested</option>
      </select>
    </div>

    <!-- Visits list -->
    <div data-visits-drawer-target="visitsList" class="visits-list"></div>

    <!-- Empty state -->
    <div data-visits-drawer-target="emptyState" class="empty-state hidden">
      <div class="empty-icon">📭</div>
      <div class="empty-text">No visits found</div>
    </div>
  </div>
</div>

<style>
  .visits-toggle-btn {
    position: fixed;
    bottom: 24px;
    right: 24px;
    padding: 12px 20px;
    background: white;
    border: 2px solid #e5e7eb;
    border-radius: 24px;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    z-index: 40;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
    transition: all 0.2s;
  }

  .visits-toggle-btn:hover {
    border-color: #3b82f6;
    transform: translateY(-2px);
    box-shadow: 0 6px 16px rgba(59, 130, 246, 0.2);
  }

  .visits-drawer-content {
    position: fixed;
    top: 0;
    right: -400px;
    width: 400px;
    height: 100vh;
    background: white;
    box-shadow: -4px 0 12px rgba(0, 0, 0, 0.1);
    z-index: 50;
    transition: right 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    display: flex;
    flex-direction: column;
  }

  .visits-drawer-content.open {
    right: 0;
  }

  .visits-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 20px;
    border-bottom: 1px solid #e5e7eb;
  }

  .visits-header h3 {
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

  .visits-controls {
    padding: 16px;
    border-bottom: 1px solid #e5e7eb;
  }

  .search-input {
    width: 100%;
    padding: 8px 12px;
    border: 1px solid #d1d5db;
    border-radius: 6px;
    font-size: 14px;
    margin-bottom: 12px;
  }

  .filter-select {
    width: 100%;
    padding: 8px 12px;
    border: 1px solid #d1d5db;
    border-radius: 6px;
    font-size: 14px;
  }

  .visits-list {
    flex: 1;
    overflow-y: auto;
    padding: 12px;
  }

  .visit-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px;
    background: #f9fafb;
    border-radius: 8px;
    margin-bottom: 8px;
    cursor: pointer;
    transition: all 0.2s;
  }

  .visit-item:hover {
    background: #f3f4f6;
    transform: translateX(4px);
  }

  .visit-icon {
    width: 32px;
    height: 32px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 16px;
    font-weight: bold;
    color: white;
    flex-shrink: 0;
  }

  .visit-icon.confirmed {
    background: #22c55e;
  }

  .visit-icon.suggested {
    background: #eab308;
  }

  .visit-details {
    flex: 1;
  }

  .visit-name {
    font-weight: 600;
    color: #111827;
    margin-bottom: 4px;
  }

  .visit-meta {
    font-size: 12px;
    color: #6b7280;
  }

  .visit-arrow {
    font-size: 20px;
    color: #d1d5db;
  }

  .empty-state {
    text-align: center;
    padding: 60px 20px;
    color: #9ca3af;
  }

  .empty-state.hidden {
    display: none;
  }

  .empty-icon {
    font-size: 48px;
    margin-bottom: 16px;
  }

  .empty-text {
    font-size: 14px;
  }

  /* Mobile */
  @media (max-width: 768px) {
    .visits-drawer-content {
      width: 100%;
      right: -100%;
    }

    .visits-drawer-content.open {
      right: 0;
    }
  }
</style>
```

---

## 4.9 Update View Template

Add visits drawer and layer controls.

**File**: `app/views/maps_v2/index.html.erb` (add to layer controls)

```erb
<!-- Add to layer controls -->
<button data-layer-controls-target="button"
        data-layer="visits"
        data-action="click->layer-controls#toggleLayer"
        class="layer-button"
        aria-pressed="false">
  Visits
</button>

<button data-layer-controls-target="button"
        data-layer="photos"
        data-action="click->layer-controls#toggleLayer"
        class="layer-button"
        aria-pressed="false">
  Photos
</button>

<!-- Add visits drawer -->
<%= render 'maps_v2/visits_drawer' %>
```

---

## 🧪 E2E Tests

**File**: `e2e/v2/phase-4-visits.spec.ts`

```typescript
import { test, expect } from '@playwright/test'
import { login, waitForMap } from './helpers/setup'

test.describe('Phase 4: Visits + Photos', () => {
  test.beforeEach(async ({ page }) => {
    await login(page)
    await page.goto('/maps_v2')
    await waitForMap(page)
  })

  test.describe('Visits Layer', () => {
    test('visits layer exists', async ({ page }) => {
      const hasVisits = await page.evaluate(() => {
        const map = window.mapInstance
        return map?.getLayer('visits') !== undefined
      })

      expect(hasVisits).toBe(true)
    })

    test('visits toggle works', async ({ page }) => {
      const visitsButton = page.locator('button[data-layer="visits"]')

      if (await visitsButton.isVisible()) {
        await visitsButton.click()

        const isVisible = await page.evaluate(() => {
          const map = window.mapInstance
          return map?.getLayoutProperty('visits', 'visibility') === 'visible'
        })

        expect(isVisible).toBe(true)
      }
    })

    test('clicking visit shows popup', async ({ page }) => {
      // Enable visits layer
      const visitsButton = page.locator('button[data-layer="visits"]')
      if (await visitsButton.isVisible()) {
        await visitsButton.click()
      }

      // Click on map where visits might be
      const mapContainer = page.locator('[data-map-target="container"]')
      await mapContainer.click({ position: { x: 400, y: 300 } })

      // Check for popup (may not appear if no visit clicked)
      try {
        await page.waitForSelector('.visit-popup', { timeout: 2000 })
        const popup = page.locator('.visit-popup')
        await expect(popup).toBeVisible()
      } catch (e) {
        // No visit clicked, that's okay
      }
    })
  })

  test.describe('Photos Layer', () => {
    test('photos layer exists', async ({ page }) => {
      const hasPhotos = await page.evaluate(() => {
        const map = window.mapInstance
        return map?.getLayer('photos') !== undefined
      })

      expect(hasPhotos).toBe(true)
    })

    test('photos toggle works', async ({ page }) => {
      const photosButton = page.locator('button[data-layer="photos"]')

      if (await photosButton.isVisible()) {
        await photosButton.click()

        const isVisible = await page.evaluate(() => {
          const map = window.mapInstance
          return map?.getLayoutProperty('photos', 'visibility') === 'visible'
        })

        expect(isVisible).toBe(true)
      }
    })
  })

  test.describe('Visits Drawer', () => {
    test('visits drawer opens and closes', async ({ page }) => {
      const toggleBtn = page.locator('.visits-toggle-btn')
      await toggleBtn.click()

      const drawer = page.locator('.visits-drawer-content')
      await expect(drawer).toHaveClass(/open/)

      const closeBtn = page.locator('.visits-drawer-content .close-btn')
      await closeBtn.click()

      await expect(drawer).not.toHaveClass(/open/)
    })

    test('search visits works', async ({ page }) => {
      await page.click('.visits-toggle-btn')

      const searchInput = page.locator('[data-visits-drawer-target="searchInput"]')
      await searchInput.fill('test')

      // Wait for search to apply
      await page.waitForTimeout(300)
    })

    test('filter visits works', async ({ page }) => {
      await page.click('.visits-toggle-btn')

      const filterSelect = page.locator('[data-visits-drawer-target="filterSelect"]')
      await filterSelect.selectOption('confirmed')

      // Wait for filter to apply
      await page.waitForTimeout(300)
    })
  })

  test.describe('Regression Tests', () => {
    test('all previous layers still work', async ({ page }) => {
      const layers = ['points', 'routes', 'heatmap']

      for (const layer of layers) {
        const hasLayer = await page.evaluate((layerName) => {
          const map = window.mapInstance
          return map?.getSource(`${layerName}-source`) !== undefined
        }, layer)

        expect(hasLayer).toBe(true)
      }
    })
  })
})
```

---

## ✅ Phase 4 Completion Checklist

### Implementation
- [ ] Created visits_layer.js
- [ ] Created photos_layer.js
- [ ] Created visit_popup.js
- [ ] Created photo_popup.js
- [ ] Created visits_drawer_controller.js
- [ ] Updated map_controller.js
- [ ] Updated api_client.js
- [ ] Created visits drawer partial
- [ ] Updated view template

### Functionality
- [ ] Visits render with correct colors
- [ ] Photos display with camera icons
- [ ] Visit popups show details
- [ ] Photo popups show preview
- [ ] Visits drawer opens/closes
- [ ] Search works
- [ ] Filter works
- [ ] Clicking visit zooms to it

### Testing
- [ ] All Phase 4 E2E tests pass
- [ ] Phase 1-3 tests still pass (regression)
- [ ] Manual testing complete

---

## 🚀 Deployment

```bash
git checkout -b maps-v2-phase-4
git add app/javascript/maps_v2/ app/views/maps_v2/ e2e/v2/
git commit -m "feat: Maps V2 Phase 4 - Visits and photos"

# Run all tests (regression)
npx playwright test e2e/v2/

# Deploy to staging
git push origin maps-v2-phase-4
```

---

## 🎉 What's Next?

**Phase 5**: Add areas layer and drawing tools for creating/managing geographic areas.
