import { BaseLayer } from './base_layer'
import maplibregl from 'maplibre-gl'
import { getCurrentTheme, getThemeColors } from '../utils/popup_theme'

/**
 * Photos layer with clustering and thumbnail markers
 * Uses MapLibre's built-in GeoJSON clustering for cluster circles,
 * and DOM markers with thumbnail images for individual (unclustered) photos.
 */
export class PhotosLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'photos', ...options })
    this.markerCache = new Map() // keyed by feature id for efficient reuse
    this.legCache = new Map()    // spider leg layer ids keyed by feature id
    this._spiderfiedMarkers = []
    this._syncMarkers = this._syncMarkers.bind(this)
    this._onClusterClick = this._onClusterClick.bind(this)
    this._onMoveEnd = this._onMoveEnd.bind(this)
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || { type: 'FeatureCollection', features: [] },
      cluster: true,
      clusterRadius: 60,
      clusterMaxZoom: 15
    }
  }

  getLayerConfigs() {
    return [
      {
        id: 'photos-clusters',
        type: 'circle',
        source: this.sourceId,
        filter: ['has', 'point_count'],
        paint: {
          'circle-color': 'rgba(59, 130, 246, 0.7)',
          'circle-radius': [
            'step',
            ['get', 'point_count'],
            20,  // default radius
            10, 25,  // >= 10 photos
            50, 30   // >= 50 photos
          ],
          'circle-stroke-width': 2,
          'circle-stroke-color': '#ffffff'
        }
      },
      {
        id: 'photos-cluster-count',
        type: 'symbol',
        source: this.sourceId,
        filter: ['has', 'point_count'],
        layout: {
          'text-field': '{point_count_abbreviated}',
          'text-size': 14,
          'text-allow-overlap': true
        },
        paint: {
          'text-color': '#ffffff'
        }
      }
    ]
  }

  getLayerIds() {
    return ['photos-clusters', 'photos-cluster-count']
  }

  async add(data) {
    this.data = data

    // Register source and cluster layers via BaseLayer
    super.add(data)

    // Cluster click → zoom in
    this.map.on('click', 'photos-clusters', this._onClusterClick)

    // Cursor changes on cluster hover
    this.map.on('mouseenter', 'photos-clusters', () => {
      this.map.getCanvas().style.cursor = 'pointer'
    })
    this.map.on('mouseleave', 'photos-clusters', () => {
      this.map.getCanvas().style.cursor = ''
    })

    // Sync DOM markers when data loads or map moves;
    // also clear any spiderfied cluster expansion on move
    this.map.on('moveend', this._onMoveEnd)

    // Also sync when source data finishes loading
    this.map.on('data', (e) => {
      if (e.sourceId === this.sourceId && e.isSourceLoaded) {
        this._syncMarkers()
      }
    })

    // Initial sync
    this._syncMarkers()
  }

  async update(data) {
    this.data = data
    const source = this.map.getSource(this.sourceId)
    if (source && source.setData) {
      source.setData(data)
    }
    // Markers will sync via the data event
  }

  _onMoveEnd() {
    this._clearSpiderfiedMarkers()
    this._syncMarkers()
  }

  _onClusterClick(e) {
    const features = this.map.queryRenderedFeatures(e.point, {
      layers: ['photos-clusters']
    })
    if (!features.length) return

    const clusterId = features[0].properties.cluster_id
    const source = this.map.getSource(this.sourceId)

    source.getClusterExpansionZoom(clusterId, (err, zoom) => {
      if (err) return

      // If expansion zoom exceeds max zoom, the cluster can't split further
      // (all points share the same coordinates). Spiderfy them directly.
      if (zoom > this.map.getMaxZoom()) {
        this._spiderfyCluster(source, clusterId, features[0].geometry.coordinates)
        return
      }

      this.map.easeTo({
        center: features[0].geometry.coordinates,
        zoom: zoom
      })
    })
  }

  /**
   * Expand a cluster that can't be split by zooming (same-coordinate points).
   * Fetches all leaves and displays them as spiderfied DOM markers.
   */
  _spiderfyCluster(source, clusterId, center) {
    source.getClusterLeaves(clusterId, Infinity, 0, (err, leaves) => {
      if (err || !leaves?.length) return

      // Remove any existing spiderfied markers
      this._clearSpiderfiedMarkers()

      const centerPx = this.map.project(center)
      const positions = this._computeSpiralPositions(leaves.length, centerPx)

      this._spiderfiedMarkers = []

      leaves.forEach((leaf, i) => {
        const lngLat = this.map.unproject([positions[i].x, positions[i].y])

        // Draw a thin line from the original position to the spiderfied position
        const line = this._createSpiderLeg(center, [lngLat.lng, lngLat.lat])
        if (line) this._spiderfiedMarkers.push({ type: 'leg', id: line })

        const marker = this._createPhotoMarker(leaf, [lngLat.lng, lngLat.lat])
        this._spiderfiedMarkers.push({ type: 'marker', ref: marker })
      })
    })
  }

  /**
   * Create a spider leg line between the cluster center and an offset marker
   */
  _createSpiderLeg(from, to) {
    const legId = `spider-leg-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`
    try {
      this.map.addSource(legId, {
        type: 'geojson',
        data: {
          type: 'Feature',
          geometry: { type: 'LineString', coordinates: [from, to] }
        }
      })
      this.map.addLayer({
        id: legId,
        type: 'line',
        source: legId,
        paint: {
          'line-color': 'rgba(59, 130, 246, 0.4)',
          'line-width': 1.5
        }
      })
      return legId
    } catch (e) {
      return null
    }
  }

  /**
   * Remove all spiderfied markers and legs
   */
  _clearSpiderfiedMarkers() {
    if (!this._spiderfiedMarkers) return

    for (const item of this._spiderfiedMarkers) {
      if (item.type === 'marker') {
        item.ref.remove()
      } else if (item.type === 'leg') {
        if (this.map.getLayer(item.id)) this.map.removeLayer(item.id)
        if (this.map.getSource(item.id)) this.map.removeSource(item.id)
      }
    }
    this._spiderfiedMarkers = []
  }

  /**
   * Sync DOM markers to currently visible unclustered photo features.
   * Creates new markers, reuses cached ones, removes stale ones,
   * and spreads overlapping markers in a circle (spiderfier).
   */
  _syncMarkers() {
    if (!this.visible) return

    const source = this.map.getSource(this.sourceId)
    if (!source) return

    // Query unclustered features from the source
    const features = this.map.querySourceFeatures(this.sourceId, {
      filter: ['!', ['has', 'point_count']]
    })

    // Deduplicate by feature id (querySourceFeatures can return dupes across tiles)
    const seen = new Map()
    for (const feature of features) {
      const id = feature.properties.id || `${feature.geometry.coordinates[0]}_${feature.geometry.coordinates[1]}`
      if (!seen.has(id)) {
        seen.set(id, feature)
      }
    }

    // Filter to current viewport
    const bounds = this.map.getBounds()
    const visibleFeatures = new Map()
    for (const [id, feature] of seen) {
      const [lng, lat] = feature.geometry.coordinates
      if (bounds.contains([lng, lat])) {
        visibleFeatures.set(id, feature)
      }
    }

    // Compute spiderfied positions for overlapping markers
    const offsets = this._computeSpiderOffsets(visibleFeatures)

    // Remove markers and legs no longer visible
    for (const [id, marker] of this.markerCache) {
      if (!visibleFeatures.has(id)) {
        marker.remove()
        this.markerCache.delete(id)
        this._removeLeg(id)
      }
    }

    // Add or update markers and legs
    for (const [id, feature] of visibleFeatures) {
      const offset = offsets.get(id)
      const origin = feature.geometry.coordinates

      if (this.markerCache.has(id)) {
        if (offset) {
          // Update marker position and leg
          this.markerCache.get(id).setLngLat(offset)
          this._updateLeg(id, origin, offset)
        } else {
          // No longer offset — reset to original position, remove leg
          this.markerCache.get(id).setLngLat(origin)
          this._removeLeg(id)
        }
      } else {
        const lngLat = offset || origin
        const marker = this._createPhotoMarker(feature, lngLat)
        this.markerCache.set(id, marker)
        if (offset) {
          this._updateLeg(id, origin, offset)
        }
      }
    }
  }

  /**
   * Group nearby features and compute offset positions so markers don't overlap.
   * Uses a spiral layout that scales well for large groups (60+ photos).
   * Returns a Map of featureId -> [offsetLng, offsetLat] for features that need moving.
   */
  _computeSpiderOffsets(visibleFeatures) {
    const offsets = new Map()
    const OVERLAP_PX = 40

    // Convert each feature to screen coordinates for proximity grouping
    const entries = []
    for (const [id, feature] of visibleFeatures) {
      const [lng, lat] = feature.geometry.coordinates
      const point = this.map.project([lng, lat])
      entries.push({ id, lng, lat, px: point.x, py: point.y })
    }

    // Group features by proximity using a simple greedy approach
    const assigned = new Set()
    const groups = []

    for (let i = 0; i < entries.length; i++) {
      if (assigned.has(entries[i].id)) continue

      const group = [entries[i]]
      assigned.add(entries[i].id)

      for (let j = i + 1; j < entries.length; j++) {
        if (assigned.has(entries[j].id)) continue

        const dx = entries[i].px - entries[j].px
        const dy = entries[i].py - entries[j].py
        if (Math.sqrt(dx * dx + dy * dy) < OVERLAP_PX) {
          group.push(entries[j])
          assigned.add(entries[j].id)
        }
      }

      if (group.length > 1) {
        groups.push(group)
      }
    }

    // For each overlapping group, compute spiral positions
    for (const group of groups) {
      const centerPx = {
        x: group.reduce((s, e) => s + e.px, 0) / group.length,
        y: group.reduce((s, e) => s + e.py, 0) / group.length
      }

      const positions = this._computeSpiralPositions(group.length, centerPx)

      group.forEach((entry, i) => {
        const lngLat = this.map.unproject([positions[i].x, positions[i].y])
        offsets.set(entry.id, [lngLat.lng, lngLat.lat])
      })
    }

    return offsets
  }

  /**
   * Compute spiral positions for N items around a center point.
   * Places items in concentric rings, each ring fitting more items,
   * with enough spacing so 50px markers don't overlap.
   */
  _computeSpiralPositions(count, center) {
    const MARKER_SIZE = 50
    const SPACING = 8
    const step = MARKER_SIZE + SPACING // distance between marker centers
    const positions = []

    if (count <= 8) {
      // Small group: single circle
      const radius = Math.max(step, (count * step) / (2 * Math.PI))
      for (let i = 0; i < count; i++) {
        const angle = (2 * Math.PI * i) / count - Math.PI / 2
        positions.push({
          x: center.x + radius * Math.cos(angle),
          y: center.y + radius * Math.sin(angle)
        })
      }
    } else {
      // Large group: concentric rings
      let placed = 0
      let ring = 1

      while (placed < count) {
        const radius = ring * step
        const circumference = 2 * Math.PI * radius
        const fitInRing = Math.min(Math.floor(circumference / step), count - placed)

        for (let i = 0; i < fitInRing; i++) {
          const angle = (2 * Math.PI * i) / fitInRing - Math.PI / 2
          positions.push({
            x: center.x + radius * Math.cos(angle),
            y: center.y + radius * Math.sin(angle)
          })
          placed++
        }
        ring++
      }
    }

    return positions
  }

  /**
   * Create or update a spider leg line from a photo's original position to its offset position.
   * Reuses existing source/layer if one already exists for this feature id.
   */
  _updateLeg(featureId, origin, offset) {
    const lineData = {
      type: 'Feature',
      geometry: { type: 'LineString', coordinates: [origin, offset] }
    }

    const legId = this.legCache.get(featureId)
    if (legId) {
      // Update existing leg
      const source = this.map.getSource(legId)
      if (source) {
        source.setData(lineData)
        return
      }
    }

    // Create new leg
    const newLegId = `photo-leg-${featureId}`
    try {
      this.map.addSource(newLegId, { type: 'geojson', data: lineData })
      this.map.addLayer({
        id: newLegId,
        type: 'line',
        source: newLegId,
        paint: {
          'line-color': 'rgba(59, 130, 246, 0.4)',
          'line-width': 1.5,
          'line-dasharray': [2, 2]
        }
      })
      this.legCache.set(featureId, newLegId)
    } catch (e) {
      // Silently ignore if source/layer already exists from a race
    }
  }

  /**
   * Remove a spider leg line for a given feature id
   */
  _removeLeg(featureId) {
    const legId = this.legCache.get(featureId)
    if (!legId) return

    if (this.map.getLayer(legId)) this.map.removeLayer(legId)
    if (this.map.getSource(legId)) this.map.removeSource(legId)
    this.legCache.delete(featureId)
  }

  /**
   * Remove all spider leg lines
   */
  _clearAllLegs() {
    for (const [id] of this.legCache) {
      this._removeLeg(id)
    }
  }

  /**
   * Create a single DOM marker for a photo feature
   * @param {Object} feature - GeoJSON feature
   * @param {Array} lngLat - [lng, lat] position (may be offset from original)
   */
  _createPhotoMarker(feature, lngLat) {
    const { thumbnail_url } = feature.properties
    const [lng, lat] = lngLat || feature.geometry.coordinates

    const container = document.createElement('div')
    container.style.display = this.visible ? 'block' : 'none'

    const el = document.createElement('div')
    el.className = 'photo-marker'
    el.style.cssText = `
      width: 50px;
      height: 50px;
      border-radius: 50%;
      cursor: pointer;
      background-size: cover;
      background-position: center;
      background-image: url('${thumbnail_url}');
      border: 3px solid white;
      box-shadow: 0 2px 4px rgba(0,0,0,0.3);
      transition: transform 0.2s, box-shadow 0.2s;
    `

    el.addEventListener('mouseenter', () => {
      el.style.transform = 'scale(1.2)'
      el.style.boxShadow = '0 4px 8px rgba(0,0,0,0.4)'
      el.style.zIndex = '1000'
    })

    el.addEventListener('mouseleave', () => {
      el.style.transform = 'scale(1)'
      el.style.boxShadow = '0 2px 4px rgba(0,0,0,0.3)'
      el.style.zIndex = '1'
    })

    el.addEventListener('click', (e) => {
      e.stopPropagation()
      this.showPhotoPopup(feature)
    })

    container.appendChild(el)

    const marker = new maplibregl.Marker({ element: container })
      .setLngLat([lng, lat])
      .addTo(this.map)

    return marker
  }

  /**
   * Show photo popup with image
   * @param {Object} feature - GeoJSON feature with photo properties
   */
  showPhotoPopup(feature) {
    const { thumbnail_url, taken_at, filename, city, state, country, type, source } = feature.properties
    const [lng, lat] = feature.geometry.coordinates

    const takenDate = taken_at ? new Date(taken_at).toLocaleString() : 'Unknown'
    const location = [city, state, country].filter(Boolean).join(', ') || 'Unknown location'
    const mediaType = type === 'VIDEO' ? '🎥 Video' : '📷 Photo'

    // Get theme colors
    const theme = getCurrentTheme()
    const colors = getThemeColors(theme)

    // Create popup HTML with theme-aware styling
    const popupHTML = `
      <div class="photo-popup" style="font-family: system-ui, -apple-system, sans-serif; max-width: 350px;">
        <div style="width: 100%; border-radius: 8px; overflow: hidden; margin-bottom: 12px; background: ${colors.backgroundAlt};">
          <img
            src="${thumbnail_url}"
            alt="${filename || 'Photo'}"
            style="width: 100%; height: auto; max-height: 350px; object-fit: contain; display: block;"
            loading="lazy"
          />
        </div>
        <div style="font-size: 13px;">
          ${filename ? `<div style="font-weight: 600; color: ${colors.textPrimary}; margin-bottom: 6px; word-wrap: break-word;">${filename}</div>` : ''}
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">📅 ${takenDate}</div>
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">📍 ${location}</div>
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">Coordinates: ${lat.toFixed(6)}, ${lng.toFixed(6)}</div>
          ${source ? `<div style="color: ${colors.textSecondary}; font-size: 11px; margin-bottom: 6px;">Source: ${source}</div>` : ''}
          <div style="font-size: 14px; margin-top: 8px; color: ${colors.textPrimary};">${mediaType}</div>
        </div>
      </div>
    `

    new maplibregl.Popup({
      closeButton: true,
      closeOnClick: true,
      maxWidth: '400px'
    })
      .setLngLat([lng, lat])
      .setHTML(popupHTML)
      .addTo(this.map)
  }

  /**
   * Clear all cached DOM markers from map
   */
  clearMarkers() {
    for (const [, marker] of this.markerCache) {
      marker.remove()
    }
    this.markerCache.clear()
    this._clearAllLegs()
  }

  /**
   * Show cluster layers and all cached DOM markers
   */
  show() {
    this.visible = true
    this.setVisibility(true)
    for (const [, marker] of this.markerCache) {
      marker.getElement().style.display = 'block'
    }
    for (const [, legId] of this.legCache) {
      if (this.map.getLayer(legId)) {
        this.map.setLayoutProperty(legId, 'visibility', 'visible')
      }
    }
    // Re-sync to pick up any features that should now be visible
    this._syncMarkers()
  }

  /**
   * Hide cluster layers and all cached DOM markers
   */
  hide() {
    this.visible = false
    this.setVisibility(false)
    this._clearSpiderfiedMarkers()
    for (const [, marker] of this.markerCache) {
      marker.getElement().style.display = 'none'
    }
    for (const [, legId] of this.legCache) {
      if (this.map.getLayer(legId)) {
        this.map.setLayoutProperty(legId, 'visibility', 'none')
      }
    }
  }

  /**
   * Remove layer, clean up markers and event listeners
   */
  remove() {
    this.clearMarkers()
    this._clearSpiderfiedMarkers()
    this.map.off('moveend', this._onMoveEnd)
    this.map.off('click', 'photos-clusters', this._onClusterClick)
    super.remove()
  }
}
